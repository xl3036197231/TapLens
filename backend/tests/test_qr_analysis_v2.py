import asyncio
import json
from copy import deepcopy
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from httpx import ASGITransport, AsyncClient, Response
from pydantic import ValidationError

from app.ai.provider import ProviderResult
from app.core.config import Settings
from app.main import create_app
from app.qr_analysis.catalog import QrFixtureCatalog
from app.qr_analysis.executor import QrAnalysisExecutor
from app.qr_analysis.models import QrAnalysisState


ROOT = Path(__file__).resolve().parents[2]
REQUEST = ROOT / "shared/fixtures/qr/qr-cloud-analysis-v2-request.json"
TEST_SECRET = "test-secret-that-is-long-enough-for-qr-v2-tests"


def test_qr_v2_catalog_is_packaged_in_backend_image() -> None:
    dockerfile = (ROOT / "backend/Dockerfile").read_text(encoding="utf-8")
    assert (
        "COPY shared/fixtures/qr/qr-cloud-fixture-catalog-v2.json "
        "/srv/taplens/shared/fixtures/qr/qr-cloud-fixture-catalog-v2.json"
    ) in dockerfile


class QrV2Provider:
    def __init__(self) -> None:
        self.calls: list[dict[str, object]] = []

    async def analyze(self, payload: dict[str, object]) -> ProviderResult:
        self.calls.append(deepcopy(payload))
        context = payload["report_context"]
        target = payload["analysis_input"]["targets"][0]
        evidence = [
            item
            for group in (payload["local_evidence"], payload["cloud_evidence"])
            for item in group["evidence"]
        ]
        ids = [item["id"] for item in evidence]
        report = {
            "schema_version": "1.0",
            "analysis_id": context["analysis_id"],
            "created_at": context["created_at"],
            "risk_level": "high",
            "consistency": "contradictory",
            "title": "固定二维码静态证据 AI 研判",
            "target": {"type": target["type"], "display": target["value"], "redacted": True},
            "summary": "模型仅解释已持久化的本地与服务端静态证据。",
            "claim": {"summary": "用户确认分析固定二维码样例", "subject": None, "purpose": None, "requested_data": [], "intended_target": None},
            "observed_behavior": {"summary": "未执行二维码动作。", "subjects": [], "purposes": [], "collected_data": [], "destinations": [], "actions": ["仅解释静态证据"], "evidence_ids": ids},
            "differences": [],
            "recommendations": ["确认来源后再执行二维码动作。"],
            "evidence": [{"id": item} for item in ids],
            "uncertainty": {"status": "partial", "summary": "没有运行时行为证据。", "reasons": ["未执行目标。"], "missing_evidence": ["真实运行行为"]},
            "sources": {"local": True, "cloud": True, "ai": False},
            "token_usage": {"request_count": 0, "prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0, "model": None},
        }
        return ProviderResult(report=report, prompt_tokens=40, completion_tokens=20, total_tokens=60, model="cuc/deepseek")


class RejectingQrV2Provider(QrV2Provider):
    async def analyze(self, payload: dict[str, object]) -> ProviderResult:
        result = await super().analyze(payload)
        result.report["evidence"] = []
        return result


def test_qr_v2_create_replay_consumes_one_quota_and_returns_deterministic_status(tmp_path) -> None:
    app = build_app(tmp_path)
    token = login(app, "QrV2_Replay")
    body = request_body()

    first = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)
    replay = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)

    assert first.status_code == 202
    assert replay.status_code == 409
    assert replay.json()["error"] == {
        "code": "CLOUD_TASK_INVALID_STATE",
        "message": "二维码分析仍在进行，请查询状态",
        "retryable": False,
        "details": {
            "status_path": first.json()["status_path"],
            "poll_after_seconds": 2,
        },
    }
    assert first.headers["location"] == first.json()["status_path"]
    assert first.headers["retry-after"] == str(first.json()["poll_after_seconds"])
    with app.state.database.connect() as connection:
        assert connection.execute("SELECT COUNT(*) FROM qr_analysis_tasks").fetchone()[0] == 1
        assert connection.execute("SELECT used FROM daily_quota_usage").fetchone()[0] == 1


def test_qr_v2_rejects_digest_mismatch_before_task_or_quota(tmp_path) -> None:
    app = build_app(tmp_path)
    token = login(app, "QrV2_Digest")
    body = request_body()
    body["sample_ref"]["payload_sha256"] = "0" * 64

    response = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)

    assert response.status_code == 422
    assert response.json()["error"]["details"]["reason"] == "fixture_digest_mismatch"
    with app.state.database.connect() as connection:
        assert connection.execute("SELECT COUNT(*) FROM qr_analysis_tasks").fetchone()[0] == 0
        assert connection.execute("SELECT COUNT(*) FROM daily_quota_usage").fetchone()[0] == 0


@pytest.mark.parametrize(
    "change",
    (
        lambda body: body.update(created_at="2026-10-09T12:00:00"),
        lambda body: body["local_evidence"]["evidence"].append(
            deepcopy(body["local_evidence"]["evidence"][0])
        ),
    ),
)
def test_qr_v2_rejects_ambiguous_time_and_duplicate_evidence_before_quota(
    tmp_path, change
) -> None:
    app = build_app(tmp_path)
    token = login(app, f"QrV2_Invalid_{uuid4().hex[:6]}")
    body = request_body()
    change(body)

    response = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "CLOUD_REQUEST_INVALID"
    with app.state.database.connect() as connection:
        assert connection.execute("SELECT COUNT(*) FROM qr_analysis_tasks").fetchone()[0] == 0
        assert connection.execute("SELECT COUNT(*) FROM daily_quota_usage").fetchone()[0] == 0


def test_qr_v2_rejects_raw_payload_in_local_evidence_before_quota(tmp_path) -> None:
    app = build_app(tmp_path)
    token = login(app, "QrV2_Raw_Payload")
    body = request_body()
    body["local_evidence"]["evidence"][0]["detail"] = (
        "intent://scan/#Intent;package=com.example.otherapp;end"
    )

    response = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)

    assert response.status_code == 422
    assert response.json()["error"]["details"] == {"reason": "raw_payload_forbidden"}
    with app.state.database.connect() as connection:
        assert connection.execute("SELECT COUNT(*) FROM qr_analysis_tasks").fetchone()[0] == 0
        assert connection.execute("SELECT COUNT(*) FROM daily_quota_usage").fetchone()[0] == 0


@pytest.mark.parametrize("field", ("code", "message"))
def test_qr_v2_rejects_sensitive_risk_hint_before_quota(tmp_path, field) -> None:
    app = build_app(tmp_path)
    token = login(app, f"QrV2_Risk_Hint_{field}")
    body = request_body()
    body["local_evidence"]["risk_hints"] = [
        {
            "code": "LOCAL_REVIEW",
            "risk_level": "high",
            "message": "已脱敏本地风险提示",
            "evidence_ids": ["L01"],
        }
    ]
    body["local_evidence"]["risk_hints"][0][field] = "password=SUPERSECRET"

    response = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)

    assert response.status_code == 422
    assert response.json()["error"]["details"] == {"reason": "raw_payload_forbidden"}
    with app.state.database.connect() as connection:
        assert connection.execute("SELECT COUNT(*) FROM qr_analysis_tasks").fetchone()[0] == 0
        assert connection.execute("SELECT COUNT(*) FROM daily_quota_usage").fetchone()[0] == 0


def test_qr_v2_rejects_risk_hint_referencing_cloud_evidence_before_quota(tmp_path) -> None:
    app = build_app(tmp_path)
    token = login(app, "QrV2_Risk_Hint_Provenance")
    body = request_body()
    body["local_evidence"]["risk_hints"] = [
        {
            "code": "LOCAL_REVIEW",
            "risk_level": "high",
            "message": "已脱敏本地风险提示",
            "evidence_ids": ["C01"],
        }
    ]

    response = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)

    assert response.status_code == 422
    with app.state.database.connect() as connection:
        assert connection.execute("SELECT COUNT(*) FROM qr_analysis_tasks").fetchone()[0] == 0
        assert connection.execute("SELECT COUNT(*) FROM daily_quota_usage").fetchone()[0] == 0


def test_qr_v2_input_change_conflicts_without_second_quota(tmp_path) -> None:
    app = build_app(tmp_path)
    token = login(app, "QrV2_Conflict")
    body = request_body()
    assert request(app, "POST", "/api/v1/qr-analyses", token=token, json=body).status_code == 202
    changed = deepcopy(body)
    changed["local_evidence"]["evidence"][0]["detail"] = "另一份已脱敏静态预览"

    response = request(app, "POST", "/api/v1/qr-analyses", token=token, json=changed)

    assert response.status_code == 409
    assert response.json()["error"]["code"] == "CLOUD_ANALYSIS_INPUT_CONFLICT"
    with app.state.database.connect() as connection:
        assert connection.execute("SELECT used FROM daily_quota_usage").fetchone()[0] == 1


def test_qr_v2_concurrent_replay_creates_one_task_and_one_quota_charge(tmp_path) -> None:
    app = build_app(tmp_path)
    token = login(app, "QrV2_Concurrent")
    body = request_body()

    async def send_many() -> list[Response]:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            return list(await asyncio.gather(*[
                client.post("/api/v1/qr-analyses", headers={"Authorization": f"Bearer {token}"}, json=body)
                for _ in range(8)
            ]))

    responses = asyncio.run(send_many())
    assert [response.status_code for response in responses].count(202) == 1
    assert [response.status_code for response in responses].count(409) == 7
    paths = {
        response.json().get("status_path")
        or response.json()["error"]["details"]["status_path"]
        for response in responses
    }
    assert len(paths) == 1
    with app.state.database.connect() as connection:
        assert connection.execute("SELECT COUNT(*) FROM qr_analysis_tasks").fetchone()[0] == 1
        assert connection.execute("SELECT used FROM daily_quota_usage").fetchone()[0] == 1


def test_qr_v2_none_mode_completes_without_provider(tmp_path) -> None:
    provider = QrV2Provider()
    app = build_app(tmp_path, provider)
    token = login(app, "QrV2_None")
    body = request_body(ai_mode="none")
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)

    run_worker_once(app, provider)
    status = request(app, "GET", created.json()["status_path"], token=token)

    assert status.status_code == 200
    result = status.json()
    assert result["state"] == "succeeded"
    assert result["usage"] == {"status": "not_started", "request_count": 0, "prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0, "model": None}
    assert result["report"]["token_usage"] == {key: value for key, value in result["usage"].items() if key != "status"}
    assert result["report"]["sources"] == {"local": True, "cloud": True, "ai": False}
    assert provider.calls == []


def test_qr_v2_school_mode_dispatches_once_after_finalized_evidence(tmp_path) -> None:
    provider = QrV2Provider()
    app = build_app(tmp_path, provider)
    token = login(app, "QrV2_School")
    body = request_body()
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)

    run_worker_once(app, provider)
    run_worker_once(app, provider)
    status = request(app, "GET", created.json()["status_path"], token=token).json()

    assert status["state"] == "succeeded"
    assert len(provider.calls) == 1
    assert status["usage"] == {"status": "known", "request_count": 1, "prompt_tokens": 40, "completion_tokens": 20, "total_tokens": 60, "model": "cuc/deepseek"}
    assert status["report"]["created_at"] == body["created_at"]
    assert status["report"]["token_usage"] == {key: value for key, value in status["usage"].items() if key != "status"}
    serialized = json.dumps(provider.calls[0], ensure_ascii=False)
    assert "fallback.example.test" not in serialized
    assert body["sample_ref"]["payload_sha256"] not in serialized
    database_bytes = (tmp_path / "taplens.db").read_bytes()
    canonical = app.state.qr_fixture_catalog.cases["QR02"].payload.encode()
    assert canonical not in database_bytes


@pytest.mark.parametrize("sample_id", [f"QR{value:02d}" for value in range(2, 14)])
def test_qr_v2_all_fixed_samples_are_static_and_never_call_provider(
    tmp_path, sample_id
) -> None:
    provider = QrV2Provider()
    app = build_app(tmp_path, provider)
    token = login(app, f"QrV2_Matrix_{sample_id}")
    body = request_body(ai_mode="none", sample_id=sample_id)
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)

    run_worker_once(app, provider)
    status = request(app, "GET", created.json()["status_path"], token=token).json()

    assert status["state"] == "succeeded"
    assert status["evidence_bundle"]["fixture_binding"]["sample_id"] == sample_id
    assert not any(status["evidence_bundle"]["execution"].values())
    assert any(
        item["source"] == "cloud" and item["observation_mode"] == "server_static"
        for item in status["evidence_bundle"]["items"]
    )
    assert app.state.qr_fixture_catalog.cases[sample_id].payload not in json.dumps(
        status["evidence_bundle"],
        ensure_ascii=False,
    )
    assert provider.calls == []


@pytest.mark.parametrize("mutation", ("user_id", "task_id", "image_received", "publisher_verified", "item_detail", "execution", "limitation", "item_order"))
def test_qr_v2_hmac_tamper_fails_before_provider(tmp_path, mutation) -> None:
    provider = QrV2Provider()
    app = build_app(tmp_path, provider)
    token = login(app, f"QrV2_Tamper_{uuid4().hex[:6]}")
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=request_body())
    repository = app.state.qr_analysis_repository
    record = repository.start(UUID(created.json()["task_id"]))
    executor = QrAnalysisExecutor(repository, app.state.qr_fixture_catalog, provider)
    case = app.state.qr_fixture_catalog.cases[record.sample_id]
    cloud, limitations = executor.analyzer.analyze(case)
    local = record.local_evidence["evidence"][0]
    from app.qr_analysis.schemas import ServerEvidenceItem
    bundle = executor._bundle(record, [ServerEvidenceItem(id=local["id"], source="local", observation_mode="device_static", kind=local["kind"], title=local["title"], detail=local["detail"]), *cloud], limitations)
    finalized = repository.finalize_evidence(task_id=record.task_id, evidence_bundle=bundle)
    tampered = finalized
    if mutation in {"user_id", "task_id"}:
        tampered = replace(finalized, **{mutation: uuid4()})
    else:
        changed = deepcopy(finalized.evidence_bundle)
        if mutation == "image_received":
            changed["fixture_binding"]["image_received"] = True
        elif mutation == "publisher_verified":
            changed["fixture_binding"]["publisher_verified"] = True
        elif mutation == "item_detail":
            changed["items"][0]["detail"] = "被篡改"
        elif mutation == "execution":
            changed["execution"]["target_accessed"] = True
        elif mutation == "limitation":
            changed["limitations"][0] = "被篡改"
        elif mutation == "item_order":
            changed["items"].reverse()
        tampered = replace(finalized, evidence_bundle=changed)

    with pytest.raises(ValueError, match="HMAC mismatch"):
        repository.verify_finalized_bundle(tampered)
    assert provider.calls == []


def test_qr_v2_bundle_rejects_unknown_fields_before_signing(tmp_path) -> None:
    provider = QrV2Provider()
    app = build_app(tmp_path, provider)
    token = login(app, "QrV2_Strict_Bundle")
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=request_body())
    repository = app.state.qr_analysis_repository
    record = repository.start(UUID(created.json()["task_id"]))
    executor = QrAnalysisExecutor(repository, app.state.qr_fixture_catalog, provider)
    cloud, limitations = executor.analyzer.analyze(
        app.state.qr_fixture_catalog.cases[record.sample_id]
    )
    local = record.local_evidence["evidence"][0]
    from app.qr_analysis.schemas import ServerEvidenceItem

    bundle = executor._bundle(
        record,
        [
            ServerEvidenceItem(
                id=local["id"],
                source="local",
                observation_mode="device_static",
                kind=local["kind"],
                title=local["title"],
                detail=local["detail"],
            ),
            *cloud,
        ],
        limitations,
    ).model_dump(mode="json")
    bundle["unexpected_contract_field"] = "must be rejected"

    with pytest.raises(ValidationError, match="extra_forbidden"):
        repository.finalize_evidence(
            task_id=record.task_id,
            evidence_bundle=bundle,
        )
    assert repository.get_by_task(record.task_id).evidence_bundle is None
    assert provider.calls == []


def test_qr_v2_report_rejection_preserves_known_usage(tmp_path) -> None:
    provider = RejectingQrV2Provider()
    app = build_app(tmp_path, provider)
    token = login(app, "QrV2_Known_Failure")
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=request_body())
    run_worker_once(app, provider)

    status = request(app, "GET", created.json()["status_path"], token=token).json()
    assert status["state"] == "failed"
    assert status["error"]["code"] == "AI_REPORT_REJECTED"
    assert status["usage"] == {"status": "known", "request_count": 1, "prompt_tokens": 40, "completion_tokens": 20, "total_tokens": 60, "model": "cuc/deepseek"}
    assert status["evidence_bundle"] is not None
    assert len(provider.calls) == 1


def test_qr_v2_evidence_failure_is_retryable_but_never_repeats_post(tmp_path, monkeypatch) -> None:
    app = build_app(tmp_path)
    token = login(app, "QrV2_Evidence_Failure")
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=request_body())

    def fail_analysis(_case):
        raise RuntimeError("synthetic static analyzer failure")

    executor = QrAnalysisExecutor(
        app.state.qr_analysis_repository,
        app.state.qr_fixture_catalog,
        app.state.ai_provider,
    )
    monkeypatch.setattr(executor.analyzer, "analyze", fail_analysis)
    asyncio.run(executor.execute(UUID(created.json()["task_id"])))

    status = request(app, "GET", created.json()["status_path"], token=token).json()
    assert status["state"] == "failed"
    assert status["error"] == {
        "code": "CLOUD_EVIDENCE_BUILD_FAILED",
        "message": "二维码云端证据生成失败",
        "retryable": True,
        "details": None,
    }
    assert status["actions"] == {"poll_status": False, "repeat_post": False}
    assert status["usage"] == {"status": "not_started"}


def test_qr_v2_recovery_requeues_before_dispatch_and_freezes_after_dispatch(tmp_path) -> None:
    provider = QrV2Provider()
    app = build_app(tmp_path, provider)
    token = login(app, "QrV2_Recovery")
    first = request(app, "POST", "/api/v1/qr-analyses", token=token, json=request_body())
    repository = app.state.qr_analysis_repository
    record = repository.start(UUID(first.json()["task_id"]))
    assert repository.recover_interrupted() == (1, 0)
    assert repository.get_by_task(record.task_id).state is QrAnalysisState.QUEUED

    run_worker_once(app, provider, stop_after_finalize=True)
    current = repository.get_by_task(record.task_id)
    assert repository.recover_interrupted() == (1, 0)
    run_worker_once(app, provider)
    assert repository.get_by_task(current.task_id).state is QrAnalysisState.SUCCEEDED
    assert len(provider.calls) == 1

    second_body = request_body()
    second = request(app, "POST", "/api/v1/qr-analyses", token=token, json=second_body)
    run_worker_once(app, provider, stop_after_finalize=True)
    current = repository.get_by_task(UUID(second.json()["task_id"]))
    repository.mark_provider_dispatch(current.task_id)
    assert repository.recover_interrupted() == (0, 1)
    assert repository.get_by_task(current.task_id).state is QrAnalysisState.OUTCOME_UNKNOWN
    run_worker_once(app, provider)
    assert len(provider.calls) == 1


def test_qr_v2_late_guarded_success_converges_without_second_dispatch(tmp_path) -> None:
    provider = QrV2Provider()
    app = build_app(tmp_path, provider)
    token = login(app, "QrV2_Late_Success")
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=request_body())
    repository = app.state.qr_analysis_repository
    run_worker_once(app, provider, stop_after_finalize=True)
    record = repository.get_by_task(UUID(created.json()["task_id"]))
    repository.mark_provider_dispatch(record.task_id)
    repository.recover_interrupted()
    trusted = QrAnalysisExecutor(
        repository,
        app.state.qr_fixture_catalog,
        provider,
    )._trusted_input(repository.get_by_task(record.task_id))
    provider_result = asyncio.run(provider.analyze(trusted.model_dump(mode="json")))
    from app.ai.guard import validate_and_finalize_report
    report = validate_and_finalize_report(
        trusted,
        provider_result,
        expected_created_at_text=record.report_created_at,
    )

    repository.complete(
        task_id=record.task_id,
        report=report,
        usage={
            "prompt_tokens": provider_result.prompt_tokens,
            "completion_tokens": provider_result.completion_tokens,
            "total_tokens": provider_result.total_tokens,
            "model": provider_result.model,
        },
    )

    status = request(app, "GET", created.json()["status_path"], token=token).json()
    assert status["state"] == "succeeded"
    assert status["usage"]["status"] == "known"
    assert len(provider.calls) == 1
    run_worker_once(app, provider)
    assert len(provider.calls) == 1


def test_qr_v2_missing_historical_hmac_keys_fail_closed(tmp_path) -> None:
    app = build_app(tmp_path)
    token = login(app, "QrV2_Key_Rotation")
    body = request_body()
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)
    repository = app.state.qr_analysis_repository
    run_worker_once(app, app.state.ai_provider, stop_after_finalize=True)
    record = repository.get_by_task(UUID(created.json()["task_id"]))

    repository.secrets.pop(record.bundle_digest_key_version)
    with pytest.raises(ValueError, match="key is unavailable"):
        repository.verify_finalized_bundle(record)
    replay = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)
    assert replay.status_code == 409
    assert replay.json()["error"]["code"] == "CLOUD_ANALYSIS_INPUT_CONFLICT"


def test_qr12_static_analysis_never_uses_network_and_reports_claim_mismatch(tmp_path) -> None:
    provider = QrV2Provider()
    app = build_app(tmp_path, provider)
    token = login(app, "QrV2_Qr12")
    body = request_body(ai_mode="none", sample_id="QR12")
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)
    run_worker_once(app, provider)
    result = request(app, "GET", created.json()["status_path"], token=token).json()
    cloud = [item for item in result["evidence_bundle"]["items"] if item["source"] == "cloud"]
    assert cloud[0]["kind"] == "http_claim_mismatch"
    assert result["evidence_bundle"]["execution"]["target_accessed"] is False
    assert provider.calls == []


def test_qr_v2_cleanup_keeps_tombstone_and_forbids_replay(tmp_path) -> None:
    app = build_app(tmp_path)
    token = login(app, "QrV2_Expired")
    body = request_body(ai_mode="none")
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)
    run_worker_once(app, None)
    app.state.qr_analysis_repository.cleanup(datetime.now(UTC) + timedelta(days=2))

    status = request(app, "GET", created.json()["status_path"], token=token).json()
    replay = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)
    assert status["state"] == "result_expired"
    assert status["report"] is None and status["evidence_bundle"] is None
    assert replay.status_code == 409
    assert replay.json()["error"]["code"] == "CLOUD_TASK_RESULT_EXPIRED"


def test_qr_v2_cleanup_expires_failed_evidence_cache(tmp_path) -> None:
    provider = RejectingQrV2Provider()
    app = build_app(tmp_path, provider)
    token = login(app, "QrV2_Failed_Expiry")
    body = request_body()
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)
    run_worker_once(app, provider)
    before = request(app, "GET", created.json()["status_path"], token=token).json()

    assert before["state"] == "failed"
    assert before["evidence_bundle"] is not None
    assert before["cache_expires_at"] is not None

    app.state.qr_analysis_repository.cleanup(datetime.now(UTC) + timedelta(days=2))
    after = request(app, "GET", created.json()["status_path"], token=token).json()

    assert after["state"] == "result_expired"
    assert after["evidence_bundle"] is None
    assert after["report"] is None
    assert after["error"]["code"] == "CLOUD_TASK_RESULT_EXPIRED"
    replay = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)
    assert replay.status_code == 409
    assert replay.json()["error"]["code"] == "CLOUD_TASK_RESULT_EXPIRED"


def test_qr_v2_cleanup_expires_outcome_unknown_evidence_cache(tmp_path) -> None:
    provider = QrV2Provider()
    app = build_app(tmp_path, provider)
    token = login(app, "QrV2_Unknown_Expiry")
    body = request_body()
    created = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)
    repository = app.state.qr_analysis_repository
    run_worker_once(app, provider, stop_after_finalize=True)
    record = repository.get_by_task(UUID(created.json()["task_id"]))
    repository.mark_provider_dispatch(record.task_id)
    assert repository.recover_interrupted() == (0, 1)
    before = request(app, "GET", created.json()["status_path"], token=token).json()

    assert before["state"] == "outcome_unknown"
    assert before["evidence_bundle"] is not None
    assert before["cache_expires_at"] is not None

    repository.cleanup(datetime.now(UTC) + timedelta(days=2))
    after = request(app, "GET", created.json()["status_path"], token=token).json()

    assert after["state"] == "result_expired"
    assert after["actions"] == {"poll_status": False, "repeat_post": False}
    assert after["evidence_bundle"] is None
    assert after["error"]["code"] == "CLOUD_TASK_RESULT_EXPIRED"
    replay = request(app, "POST", "/api/v1/qr-analyses", token=token, json=body)
    assert replay.status_code == 409
    assert replay.json()["error"]["code"] == "CLOUD_TASK_RESULT_EXPIRED"


def build_app(tmp_path, provider=None):
    settings = Settings(environment="test", database_path=tmp_path / "taplens.db", jwt_secret=TEST_SECRET)
    app = create_app(settings)
    app.state.ai_provider = provider or QrV2Provider()
    app.state.database.initialize()
    return app


def request_body(*, ai_mode: str = "school", sample_id: str = "QR02") -> dict:
    body = json.loads(REQUEST.read_text(encoding="utf-8"))
    body["analysis_id"] = str(uuid4())
    body["ai_mode"] = ai_mode
    body["consent"]["ai_call_confirmed"] = ai_mode == "school"
    if sample_id != "QR02":
        case = QrFixtureCatalog().cases[sample_id]
        body["sample_ref"]["sample_id"] = sample_id
        body["sample_ref"]["payload_sha256"] = case.payload_sha256
    return body


def login(app, username: str) -> str:
    credentials = {"username": username, "password": "correct-horse"}
    assert request(app, "POST", "/api/v1/auth/register", json=credentials).status_code == 201
    return request(app, "POST", "/api/v1/auth/login", json=credentials).json()["access_token"]


def request(app, method: str, path: str, *, token: str | None = None, **kwargs) -> Response:
    async def send() -> Response:
        headers = kwargs.pop("headers", {})
        if token:
            headers["Authorization"] = f"Bearer {token}"
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver") as client:
            return await client.request(method, path, headers=headers, **kwargs)
    return asyncio.run(send())


def run_worker_once(app, provider, *, stop_after_finalize: bool = False) -> None:
    async def run() -> None:
        executor = QrAnalysisExecutor(app.state.qr_analysis_repository, app.state.qr_fixture_catalog, provider)
        for record in app.state.qr_analysis_repository.list_queued():
            if not stop_after_finalize:
                await executor.execute(record.task_id)
                continue
            started = app.state.qr_analysis_repository.start(record.task_id)
            case = app.state.qr_fixture_catalog.cases[started.sample_id]
            cloud, limitations = executor.analyzer.analyze(case)
            from app.qr_analysis.schemas import ServerEvidenceItem
            local = started.local_evidence["evidence"][0]
            bundle = executor._bundle(started, [ServerEvidenceItem(id=local["id"], source="local", observation_mode="device_static", kind=local["kind"], title=local["title"], detail=local["detail"]), *cloud], limitations)
            app.state.qr_analysis_repository.finalize_evidence(task_id=started.task_id, evidence_bundle=bundle)
    asyncio.run(run())
