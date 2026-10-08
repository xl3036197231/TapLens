import asyncio
import json
from copy import deepcopy
from pathlib import Path
from uuid import uuid4

import pytest
from httpx import ASGITransport, AsyncClient, Response

from app.ai.provider import ProviderResult
from app.ai.schemas import AiAnalyzeRequest
from app.core.config import Settings
from app.main import create_app


TEST_SECRET = "test-secret-that-is-long-enough-for-qr-ai-contract"
ROOT = Path(__file__).resolve().parents[2]
QR_REQUEST_FIXTURE = ROOT / "shared/fixtures/ai/qr-ai-only-request.json"
QR_CASES = (
    ("intent", "deep_link", ["open_app", "open_fallback_url"]),
    ("wifi", "qr_payload", ["connect_wifi"]),
    ("sms", "qr_payload", ["send_sms"]),
    ("phone", "qr_payload", ["place_call"]),
    ("email", "qr_payload", ["compose_email"]),
    ("contact", "qr_payload", ["import_contact"]),
    ("apk", "qr_payload", ["download_apk"]),
    ("app_store", "qr_payload", ["open_app_store"]),
    ("plain_text", "qr_payload", ["display_text"]),
    ("invalid", "qr_payload", ["unknown"]),
)


class QrFakeProvider:
    def __init__(self, *, invent_cloud_evidence: bool = False) -> None:
        self.calls: list[dict[str, object]] = []
        self.invent_cloud_evidence = invent_cloud_evidence

    async def analyze(self, payload: dict[str, object]) -> ProviderResult:
        self.calls.append(deepcopy(payload))
        context = payload["report_context"]
        analysis_input = payload["analysis_input"]
        target = analysis_input["targets"][0]
        evidence_ids = [
            item["id"] for item in payload["local_evidence"]["evidence"]
        ]
        if self.invent_cloud_evidence:
            evidence_ids.append("C99")
        report = {
            "schema_version": "1.0",
            "analysis_id": context["analysis_id"],
            "created_at": context["created_at"],
            "risk_level": "insufficient_evidence",
            "consistency": "unknown",
            "title": "二维码脱敏摘要 AI 研判",
            "target": {
                "type": target["type"],
                "display": target["value"],
                "redacted": True,
            },
            "summary": "仅分析手机提交的脱敏摘要，未访问或执行二维码目标。",
            "claim": {
                "summary": "分析二维码可能触发的行为",
                "subject": None,
                "purpose": None,
                "requested_data": [],
                "intended_target": None,
            },
            "observed_behavior": {
                "summary": "手机仅完成静态解析，未执行外部动作。",
                "subjects": [],
                "purposes": [],
                "collected_data": [],
                "destinations": [],
                "actions": ["仅分析脱敏摘要"],
                "evidence_ids": evidence_ids,
            },
            "differences": [],
            "recommendations": ["确认载荷来源后再决定是否执行。"],
            "evidence": [{"id": item} for item in evidence_ids],
            "uncertainty": {
                "status": "insufficient",
                "summary": "没有访问目标，无法确认其真实行为。",
                "reasons": ["只有本地静态证据。"],
                "missing_evidence": ["目标的真实运行行为"],
            },
            "sources": {"local": True, "cloud": False, "ai": False},
            "token_usage": {
                "request_count": 0,
                "prompt_tokens": 0,
                "completion_tokens": 0,
                "total_tokens": 0,
                "model": None,
            },
        }
        return ProviderResult(
            report=report,
            prompt_tokens=30,
            completion_tokens=20,
            total_tokens=50,
            model="cuc/deepseek",
        )


def test_frozen_qr_ai_only_fixture_matches_backend_schema() -> None:
    payload = json.loads(QR_REQUEST_FIXTURE.read_text(encoding="utf-8"))

    validated = AiAnalyzeRequest.model_validate(payload)

    assert validated.analysis_input.qr_summary is not None
    assert validated.analysis_input.qr_summary.payload_type == "wifi"
    assert validated.cloud_evidence is None


@pytest.mark.parametrize(("payload_type", "target_type", "actions"), QR_CASES)
def test_qr_ai_only_matrix_uses_no_cloud_task(
    tmp_path,
    payload_type: str,
    target_type: str,
    actions: list[str],
) -> None:
    provider = QrFakeProvider()
    app = build_app(tmp_path, provider)
    token = register_and_login(app, f"Qr_{payload_type}_User")
    request_body = qr_body(payload_type, target_type, actions)

    response = request(
        app,
        "POST",
        "/api/v1/ai/analyze",
        token=token,
        json=request_body,
    )

    assert response.status_code == 200
    assert response.json()["report"]["sources"] == {
        "local": True,
        "cloud": False,
        "ai": True,
    }
    assert len(provider.calls) == 1
    assert provider.calls[0]["cloud_evidence"] is None
    serialized_provider_input = json.dumps(provider.calls[0], ensure_ascii=False)
    assert "fallback.example.test" not in serialized_provider_input
    assert "download.example.test" not in serialized_provider_input
    assert "NOT_A_REAL_PASSWORD" not in serialized_provider_input
    assert "+00000000000" not in serialized_provider_input
    assert "TapLens training only" not in serialized_provider_input
    with app.state.database.connect() as connection:
        assert connection.execute("SELECT COUNT(*) FROM cloud_scan_tasks").fetchone()[0] == 0


def test_qr_ai_only_replay_dispatches_provider_once(tmp_path) -> None:
    provider = QrFakeProvider()
    app = build_app(tmp_path, provider)
    token = register_and_login(app, "Qr_Replay_User")
    body = qr_body("wifi", "qr_payload", ["connect_wifi"])

    first = request(app, "POST", "/api/v1/ai/analyze", token=token, json=body)
    replay = request(app, "POST", "/api/v1/ai/analyze", token=token, json=body)

    assert first.status_code == replay.status_code == 200
    assert first.json() == replay.json()
    assert len(provider.calls) == 1


def test_qr_summary_change_is_an_idempotency_conflict(tmp_path) -> None:
    provider = QrFakeProvider()
    app = build_app(tmp_path, provider)
    token = register_and_login(app, "Qr_Summary_Conflict_User")
    body = qr_body("intent", "deep_link", ["open_app"])
    changed = deepcopy(body)
    changed["analysis_input"]["qr_summary"]["possible_actions"] = [
        "open_fallback_url"
    ]

    first = request(app, "POST", "/api/v1/ai/analyze", token=token, json=body)
    conflict = request(
        app,
        "POST",
        "/api/v1/ai/analyze",
        token=token,
        json=changed,
    )

    assert first.status_code == 200
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "AI_ANALYSIS_INPUT_CONFLICT"
    assert len(provider.calls) == 1


@pytest.mark.parametrize(
    "mutate",
    (
        lambda body: body["analysis_input"]["targets"][0].update(
            {"value": "taplens-qr:wifi-password-secret"}
        ),
        lambda body: body["analysis_input"]["targets"][0].update(
            {"redacted": False}
        ),
        lambda body: body["analysis_input"]["qr_summary"].update(
            {"raw_image_sent": True}
        ),
        lambda body: body["analysis_input"]["qr_summary"].update(
            {"possible_actions": ["download_apk"]}
        ),
        lambda body: body["analysis_input"]["targets"][0].update(
            {"type": "deep_link", "value": "taplens-deeplink:wifi"}
        ),
        lambda body: body["local_evidence"]["evidence"][0].update(
            {"detail": "WiFi password=training-secret"}
        ),
        lambda body: body["local_evidence"]["evidence"][0].update(
            {"detail": "fallback https://fallback.example.test/welcome"}
        ),
        lambda body: body["local_evidence"]["evidence"][0].update(
            {"detail": "短信号码 +00000000000"}
        ),
        lambda body: body.update(
            {
                "cloud_evidence": {
                    "evidence": [{"id": "C01", "detail": "不应存在"}],
                    "risk_hints": [],
                }
            }
        ),
        lambda body: body.update(
            {
                "hard_risk_findings": [
                    {
                        "code": "LOCAL_RAW_VALUE",
                        "risk_level": "high",
                        "message": "fallback https://fallback.example.test/welcome",
                        "evidence_ids": ["L01"],
                    }
                ]
            }
        ),
    ),
)
def test_qr_ai_only_rejects_unfrozen_or_sensitive_payloads(tmp_path, mutate) -> None:
    provider = QrFakeProvider()
    app = build_app(tmp_path, provider)
    token = register_and_login(app, f"Qr_Reject_{uuid4().hex[:8]}")
    body = qr_body("wifi", "qr_payload", ["connect_wifi"])
    mutate(body)

    response = request(app, "POST", "/api/v1/ai/analyze", token=token, json=body)

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "AI_REQUEST_INVALID"
    assert provider.calls == []


def test_qr_report_guard_rejects_invented_cloud_evidence(tmp_path) -> None:
    provider = QrFakeProvider(invent_cloud_evidence=True)
    app = build_app(tmp_path, provider)
    token = register_and_login(app, "Qr_Invented_Cloud_User")

    response = request(
        app,
        "POST",
        "/api/v1/ai/analyze",
        token=token,
        json=qr_body("apk", "qr_payload", ["download_apk"]),
    )

    assert response.status_code == 502
    assert response.json()["error"]["code"] == "AI_REPORT_REJECTED"
    assert len(provider.calls) == 1


def qr_body(payload_type: str, target_type: str, actions: list[str]) -> dict:
    prefix = "taplens-deeplink" if target_type == "deep_link" else "taplens-qr"
    return {
        "report_context": {
            "analysis_id": str(uuid4()),
            "created_at": "2026-10-08T00:00:00.000000Z",
        },
        "analysis_input": {
            "claims_text": "用户确认只发送二维码脱敏类型和本地静态证据，未执行外部动作。",
            "targets": [
                {
                    "type": target_type,
                    "value": f"{prefix}:{payload_type}",
                    "label": "二维码脱敏摘要",
                    "redacted": True,
                }
            ],
            "qr_summary": {
                "payload_type": payload_type,
                "possible_actions": actions,
                "redacted": True,
                "raw_image_sent": False,
                "target_accessed": False,
                "sensitive_values_omitted": True,
            },
        },
        "local_evidence": {
            "evidence": [
                {
                    "id": "L01",
                    "kind": "qr_payload",
                    "title": "二维码静态类型",
                    "detail": f"识别为 {payload_type} 类型；敏感值已省略，未执行外部动作。",
                }
            ],
            "risk_hints": [],
        },
        "cloud_evidence": None,
        "hard_risk_findings": [],
    }


def build_app(tmp_path, provider: QrFakeProvider):
    settings = Settings(
        environment="test",
        database_path=tmp_path / "taplens-qr-ai-test.db",
        artifact_directory=tmp_path / "artifacts",
        jwt_secret=TEST_SECRET,
    )
    app = create_app(settings)
    app.state.database.initialize()
    app.state.ai_provider = provider
    return app


def register_and_login(app, username: str) -> str:
    credentials = {"username": username, "password": "correct-horse"}
    assert request(app, "POST", "/api/v1/auth/register", json=credentials).status_code == 201
    response = request(app, "POST", "/api/v1/auth/login", json=credentials)
    assert response.status_code == 200
    return response.json()["access_token"]


def request(
    app,
    method: str,
    path: str,
    *,
    token: str | None = None,
    **kwargs,
) -> Response:
    async def send() -> Response:
        headers = kwargs.pop("headers", {})
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await client.request(method, path, headers=headers, **kwargs)

    return asyncio.run(send())
