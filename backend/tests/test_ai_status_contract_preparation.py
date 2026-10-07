import json
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

from app.ai.provider import ProviderResult
from app.ai.schemas import AiAnalyzeRequest
from app.ai.status_contract import project_ai_status
from app.storage.ai_calls import AiCallRepository
from app.storage.database import Database


ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = ROOT / "shared/contracts"
REQUEST = ROOT / "shared/fixtures/ai/day5-school-model-request.json"
REPORT = ROOT / "shared/fixtures/ai/day5-school-model-mock-report.json"
NOW = datetime(2026, 10, 6, 12, 0, tzinfo=UTC)


def test_frozen_contract_projects_all_six_public_states_without_internal_fields(tmp_path) -> None:
    status_validator = validator()
    samples: list[dict[str, object]] = []

    repository, user_id, analysis_id, body = setup_repository(tmp_path / "missing")
    samples.append(project_ai_status(analysis_id=analysis_id, record=None, now=NOW))

    acquired = repository.reserve(
        user_id=user_id, analysis_id=analysis_id, payload=body, now=NOW
    )
    samples.append(
        project_ai_status(analysis_id=analysis_id, record=acquired.record, now=NOW)
    )
    repository.mark_provider_dispatch_started(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        now=NOW,
    )
    unknown = repository.complete_failure(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        error_code="AI_PROVIDER_TIMEOUT",
        outcome_unknown=True,
        now=NOW,
    )
    samples.append(project_ai_status(analysis_id=analysis_id, record=unknown, now=NOW))

    success_repository, success_user, success_id, success_body = setup_repository(
        tmp_path / "success"
    )
    success = complete_success(success_repository, success_user, success_id, success_body)
    samples.append(project_ai_status(analysis_id=success_id, record=success, now=NOW))
    samples.append(
        project_ai_status(
            analysis_id=success_id,
            record=success,
            now=NOW + timedelta(hours=25),
        )
    )

    failed_repository, failed_user, failed_id, failed_body = setup_repository(
        tmp_path / "failed"
    )
    failed_attempt = failed_repository.reserve(
        user_id=failed_user, analysis_id=failed_id, payload=failed_body, now=NOW
    )
    failed_repository.mark_provider_dispatch_started(
        user_id=failed_user,
        analysis_id=failed_id,
        attempt_id=failed_attempt.record.attempt_id,
        now=NOW,
    )
    failed = failed_repository.complete_failure(
        user_id=failed_user,
        analysis_id=failed_id,
        attempt_id=failed_attempt.record.attempt_id,
        error_code="AI_REPORT_GUARD_REJECTED",
        usage=(120, 80, 200, "cuc/deepseek"),
        now=NOW,
    )
    samples.append(project_ai_status(analysis_id=failed_id, record=failed, now=NOW))

    assert {sample["status"] for sample in samples} == {
        "not_found",
        "in_progress",
        "outcome_unknown",
        "succeeded",
        "result_expired",
        "failed",
    }
    for sample in samples:
        assert list(status_validator.iter_errors(sample)) == []
        encoded = json.dumps(sample, ensure_ascii=False)
        for forbidden in (
            "user_id",
            "attempt_id",
            "lease_expires_at",
            "provider_dispatch_started_at",
            "input_digest",
            "digest_key_version",
            "cache_expires_at",
        ):
            assert forbidden not in encoded


def test_expired_dispatched_lease_is_projected_unknown_without_mutating_sqlite(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(
        tmp_path, lease_seconds=10
    )
    acquired = repository.reserve(
        user_id=user_id, analysis_id=analysis_id, payload=body, now=NOW
    )
    dispatched = repository.mark_provider_dispatch_started(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        now=NOW,
    )

    before = repository.database.path.read_bytes()
    payload = project_ai_status(
        analysis_id=analysis_id,
        record=dispatched,
        now=NOW + timedelta(seconds=11),
    )
    after = repository.database.path.read_bytes()

    assert payload == {
        "analysis_id": str(analysis_id),
        "status": "outcome_unknown",
        "usage_status": "unknown",
    }
    assert before == after


def test_expired_undispatched_lease_is_projected_failed_without_mutating_sqlite(
    tmp_path,
) -> None:
    repository, user_id, analysis_id, body = setup_repository(
        tmp_path, lease_seconds=10
    )
    acquired = repository.reserve(
        user_id=user_id, analysis_id=analysis_id, payload=body, now=NOW
    )

    before = repository.database.path.read_bytes()
    payload = project_ai_status(
        analysis_id=analysis_id,
        record=acquired.record,
        now=NOW + timedelta(seconds=11),
    )
    after = repository.database.path.read_bytes()

    assert payload == {
        "analysis_id": str(analysis_id),
        "status": "failed",
        "failure": {
            "stage": "before_provider",
            "code": "AI_DISPATCH_NOT_STARTED",
            "retryable": False,
        },
        "usage_status": "not_applicable",
    }
    assert list(validator().iter_errors(payload)) == []
    assert before == after


def test_failed_before_provider_has_no_usage_and_status_projection_is_pure(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = repository.reserve(
        user_id=user_id, analysis_id=analysis_id, payload=body, now=NOW
    )
    failed = repository.complete_failure(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        error_code="AI_DISPATCH_PRECONDITION_FAILED",
        now=NOW,
    )

    payload = project_ai_status(analysis_id=analysis_id, record=failed, now=NOW)

    assert payload["failure"] == {
        "stage": "before_provider",
        "code": "AI_DISPATCH_PRECONDITION_FAILED",
        "retryable": False,
    }
    assert payload["usage_status"] == "not_applicable"
    assert "usage" not in payload
    assert repository.get_for_owner(user_id=user_id, analysis_id=analysis_id) == failed


def test_projection_fails_closed_for_non_contract_failure_code(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = repository.reserve(
        user_id=user_id, analysis_id=analysis_id, payload=body, now=NOW
    )
    failed = repository.complete_failure(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        error_code="AI_VALID_FAILURE",
        now=NOW,
    )

    invalid = replace(failed, error_code="PRIVATE failure text")

    try:
        project_ai_status(analysis_id=analysis_id, record=invalid, now=NOW)
    except ValueError as error:
        assert "stable error code" in str(error)
    else:
        raise AssertionError("non-contract failure code was exposed")


def test_projection_rejects_invalid_poll_interval_without_touching_record(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = repository.reserve(
        user_id=user_id, analysis_id=analysis_id, payload=body, now=NOW
    )

    try:
        project_ai_status(
            analysis_id=analysis_id,
            record=acquired.record,
            now=NOW,
            poll_after_seconds=11,
        )
    except ValueError as error:
        assert "between 1 and 10" in str(error)
    else:
        raise AssertionError("invalid polling interval was accepted")

    assert repository.get_for_owner(user_id=user_id, analysis_id=analysis_id) == acquired.record


def test_status_lookup_isolated_by_owner_projects_other_user_as_not_found(tmp_path) -> None:
    repository, owner_id, analysis_id, body = setup_repository(tmp_path)
    repository.reserve(
        user_id=owner_id, analysis_id=analysis_id, payload=body, now=NOW
    )
    other_user = uuid4()
    with repository.database.connect() as connection:
        connection.execute(
            """
            INSERT INTO users (id, username, username_normalized, password_hash, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                str(other_user),
                f"user-{other_user}",
                f"user-{other_user}",
                "not-a-real-password-hash",
                NOW.isoformat(),
            ),
        )

    other_record = repository.get_for_owner(
        user_id=other_user, analysis_id=analysis_id
    )
    payload = project_ai_status(
        analysis_id=analysis_id, record=other_record, now=NOW
    )

    assert payload == {"analysis_id": str(analysis_id), "status": "not_found"}


def test_success_cache_expiry_boundary_and_corrupt_cache_fail_closed(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    success = complete_success(repository, user_id, analysis_id, body)
    assert success.cache_expires_at is not None

    before_expiry = project_ai_status(
        analysis_id=analysis_id,
        record=success,
        now=success.cache_expires_at - timedelta(microseconds=1),
    )
    at_expiry = project_ai_status(
        analysis_id=analysis_id,
        record=success,
        now=success.cache_expires_at,
    )

    assert before_expiry["status"] == "succeeded"
    assert at_expiry == {
        "analysis_id": str(analysis_id),
        "status": "result_expired",
        "usage_status": "known",
    }

    corrupt = replace(success, response={"report": {"title": "partial"}})
    try:
        project_ai_status(analysis_id=analysis_id, record=corrupt, now=NOW)
    except ValueError as error:
        assert "incomplete" in str(error)
    else:
        raise AssertionError("corrupt cached result was exposed")


def test_projection_rejects_record_for_another_analysis(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = repository.reserve(
        user_id=user_id, analysis_id=analysis_id, payload=body, now=NOW
    )

    try:
        project_ai_status(
            analysis_id=uuid4(), record=acquired.record, now=NOW
        )
    except ValueError as error:
        assert "another analysis" in str(error)
    else:
        raise AssertionError("cross-analysis record was projected")


def setup_repository(path: Path, *, lease_seconds: int = 90):
    path.mkdir(parents=True, exist_ok=True)
    database = Database(path / "taplens-test.db")
    database.initialize()
    user_id = uuid4()
    with database.connect() as connection:
        connection.execute(
            """
            INSERT INTO users (id, username, username_normalized, password_hash, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            (
                str(user_id),
                f"user-{user_id}",
                f"user-{user_id}",
                "not-a-real-password-hash",
                NOW.isoformat(),
            ),
        )
    repository = AiCallRepository(
        database,
        digest_secrets={1: "day9-local-test-secret"},
        active_digest_key_version=1,
        lease_seconds=lease_seconds,
    )
    body = json.loads(REQUEST.read_text(encoding="utf-8"))
    analysis_id = UUID(body["report_context"]["analysis_id"])
    return repository, user_id, analysis_id, body


def complete_success(repository, user_id, analysis_id, body):
    acquired = repository.reserve(
        user_id=user_id, analysis_id=analysis_id, payload=body, now=NOW
    )
    repository.mark_provider_dispatch_started(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        now=NOW,
    )
    result = ProviderResult(
        report=json.loads(REPORT.read_text(encoding="utf-8")),
        prompt_tokens=120,
        completion_tokens=80,
        total_tokens=200,
        model="cuc/deepseek",
    )
    return repository.complete_guarded_success(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        payload=AiAnalyzeRequest.model_validate(body),
        result=result,
        now=NOW,
    )


def validator() -> Draft202012Validator:
    common = json.loads((CONTRACTS / "common.schema.json").read_text(encoding="utf-8"))
    report = json.loads(
        (CONTRACTS / "analysis-report.schema.json").read_text(encoding="utf-8")
    )
    status = json.loads(
        (CONTRACTS / "ai-analysis-status.schema.json").read_text(encoding="utf-8")
    )
    registry = Registry().with_resources(
        [
            (common["$id"], Resource.from_contents(common)),
            (report["$id"], Resource.from_contents(report)),
        ]
    )
    Draft202012Validator.check_schema(status)
    return Draft202012Validator(
        status,
        registry=registry,
        format_checker=FormatChecker(),
    )
