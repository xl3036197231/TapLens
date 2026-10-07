import asyncio
import json
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import pytest

from app.ai.provider import ProviderResult
from app.ai.schemas import AiAnalyzeRequest
from app.ai.status_contract import project_ai_status
from app.core.errors import AppError
from app.storage.ai_calls import (
    AiCallCleanupWorker,
    AiCallRepository,
    AiCallState,
    AiDispatchLeaseExpiredError,
    ReservationKind,
    UnsafeCacheResponseError,
    UsageStatus,
)
from app.storage.database import Database


ROOT = Path(__file__).resolve().parents[2]
REQUEST_FIXTURE = ROOT / "shared/fixtures/ai/day5-school-model-request.json"
REPORT_FIXTURE = ROOT / "shared/fixtures/ai/day5-school-model-mock-report.json"
NOW = datetime(2026, 9, 29, 12, 0, tzinfo=UTC)


def test_concurrent_same_analysis_acquires_one_provider_slot(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(
            pool.map(
                lambda _: reserve(repository, user_id, analysis_id, body),
                range(2),
            )
        )

    assert sorted(result.kind for result in results) == sorted(
        [ReservationKind.ACQUIRED, ReservationKind.IN_PROGRESS]
    )
    assert len({result.record.attempt_id for result in results}) == 1


def test_successful_guarded_result_is_cached_without_new_attempt(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = dispatch(repository, user_id, analysis_id, body)
    completed = complete(repository, user_id, analysis_id, acquired.record.attempt_id, body)

    replay = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(hours=1),
    )

    assert replay.kind is ReservationKind.CACHED
    assert replay.record.response == completed.response
    assert replay.record.response["report"]["sources"]["ai"] is True
    assert replay.record.usage_status is UsageStatus.KNOWN
    assert replay.record.total_tokens == 200
    assert replay.record.attempt_id == acquired.record.attempt_id


def test_same_analysis_with_different_input_is_conflict(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    reserve(repository, user_id, analysis_id, body)
    changed = deepcopy(body)
    changed["analysis_input"]["claims_text"] = "changed sanitized claim"

    conflict = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=changed,
        now=NOW,
    )

    assert conflict.kind is ReservationKind.INPUT_CONFLICT
    with repository.database.connect() as connection:
        count = connection.execute(
            "SELECT COUNT(*) FROM ai_analysis_calls WHERE user_id = ? AND analysis_id = ?",
            (str(user_id), str(analysis_id)),
        ).fetchone()[0]
    assert count == 1


def test_same_analysis_with_changed_created_at_is_conflict(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = dispatch(repository, user_id, analysis_id, body)
    complete(repository, user_id, analysis_id, acquired.record.attempt_id, body)
    changed = deepcopy(body)
    changed["report_context"]["created_at"] = "2030-01-01T00:00:00Z"

    conflict = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=changed,
        now=NOW + timedelta(hours=1),
    )

    assert conflict.kind is ReservationKind.INPUT_CONFLICT
    assert conflict.record.response["report"]["created_at"] == body["report_context"]["created_at"]


def test_same_instant_with_different_created_at_text_is_conflict(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = dispatch(repository, user_id, analysis_id, body)
    complete(repository, user_id, analysis_id, acquired.record.attempt_id, body)
    changed = deepcopy(body)
    changed["report_context"]["created_at"] = "2026-09-27T18:57:59.786849+08:00"

    conflict = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=changed,
        now=NOW + timedelta(hours=1),
    )

    assert conflict.kind is ReservationKind.INPUT_CONFLICT
    assert conflict.record.response["report"]["created_at"] == body["report_context"]["created_at"]


def test_same_analysis_is_isolated_between_users(tmp_path) -> None:
    repository, first_user, analysis_id, body = setup_repository(tmp_path)
    second_user = create_user(repository.database)

    first = reserve(repository, first_user, analysis_id, body)
    second = reserve(repository, second_user, analysis_id, body)

    assert first.kind is ReservationKind.ACQUIRED
    assert second.kind is ReservationKind.ACQUIRED
    assert first.record.attempt_id != second.record.attempt_id


def test_guard_rejection_after_dispatch_is_terminal_and_keeps_known_usage(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = dispatch(repository, user_id, analysis_id, body)
    failed = repository.complete_failure(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        error_code="AI_REPORT_REJECTED",
        usage=(120, 80, 200, "cuc/deepseek"),
        now=NOW,
    )

    replay = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(minutes=1),
    )

    assert failed.state is AiCallState.FAILED_AFTER_PROVIDER
    assert failed.usage_status is UsageStatus.KNOWN
    assert failed.total_tokens == 200
    assert replay.kind is ReservationKind.TERMINAL_FAILURE


def test_expired_dispatched_lease_becomes_unknown_and_never_reacquires(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path, lease_seconds=10)
    acquired = dispatch(repository, user_id, analysis_id, body)

    first_replay = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(seconds=11),
    )
    second_replay = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(days=1),
    )

    assert first_replay.kind is ReservationKind.OUTCOME_UNKNOWN
    assert first_replay.record.error_code == "AI_OUTCOME_UNKNOWN"
    assert first_replay.record.retryable is False
    assert second_replay.kind is ReservationKind.OUTCOME_UNKNOWN
    assert second_replay.record.attempt_id == acquired.record.attempt_id


def test_expired_undispatched_lease_closes_without_provider_reacquire(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path, lease_seconds=10)
    acquired = reserve(repository, user_id, analysis_id, body)

    retry = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(seconds=11),
    )

    assert retry.kind is ReservationKind.TERMINAL_FAILURE
    assert retry.record.attempt_id == acquired.record.attempt_id
    assert retry.record.state is AiCallState.FAILED_BEFORE_PROVIDER
    assert retry.record.error_code == "AI_DISPATCH_NOT_STARTED"
    assert retry.record.usage_status is UsageStatus.NOT_APPLICABLE
    assert retry.record.provider_dispatch_started_at is None
    with pytest.raises(AiDispatchLeaseExpiredError):
        repository.mark_provider_dispatch_started(
            user_id=user_id,
            analysis_id=analysis_id,
            attempt_id=acquired.record.attempt_id,
            now=NOW + timedelta(seconds=12),
        )


def test_expired_undispatched_attempt_cannot_mark_late_dispatch(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(
        tmp_path, lease_seconds=10
    )
    acquired = reserve(repository, user_id, analysis_id, body)

    status = project_ai_status(
        analysis_id=analysis_id,
        record=acquired.record,
        now=NOW + timedelta(seconds=11),
    )
    with pytest.raises(AiDispatchLeaseExpiredError):
        repository.mark_provider_dispatch_started(
            user_id=user_id,
            analysis_id=analysis_id,
            attempt_id=acquired.record.attempt_id,
            now=NOW + timedelta(seconds=12),
        )

    record = repository.get_for_owner(user_id=user_id, analysis_id=analysis_id)
    assert status["failure"]["code"] == "AI_DISPATCH_NOT_STARTED"
    assert record is not None
    assert record.state is AiCallState.FAILED_BEFORE_PROVIDER
    assert record.error_code == "AI_DISPATCH_NOT_STARTED"
    assert record.provider_dispatch_started_at is None


def test_lease_renewal_keeps_long_running_attempt_in_progress(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path, lease_seconds=10)
    acquired = dispatch(repository, user_id, analysis_id, body)
    renewed = repository.renew_lease(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        now=NOW + timedelta(seconds=8),
    )

    replay = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(seconds=11),
    )

    assert renewed.lease_expires_at == NOW + timedelta(seconds=18)
    assert replay.kind is ReservationKind.IN_PROGRESS


def test_same_attempt_late_success_converges_after_unknown_transition(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path, lease_seconds=10)
    acquired = dispatch(repository, user_id, analysis_id, body)
    unknown = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(seconds=11),
    )

    completed = complete(
        repository,
        user_id,
        analysis_id,
        acquired.record.attempt_id,
        body,
        now=NOW + timedelta(seconds=12),
    )

    assert unknown.kind is ReservationKind.OUTCOME_UNKNOWN
    assert completed.state is AiCallState.SUCCEEDED
    assert completed.response["report"]["sources"]["ai"] is True


def test_same_attempt_late_failure_converges_with_known_usage(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path, lease_seconds=10)
    acquired = dispatch(repository, user_id, analysis_id, body)
    unknown = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(seconds=11),
    )

    failed = repository.complete_failure(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        error_code="AI_PROVIDER_RESPONSE_INVALID",
        usage=(120, 80, 200, "cuc/deepseek"),
        now=NOW + timedelta(seconds=12),
    )

    assert unknown.kind is ReservationKind.OUTCOME_UNKNOWN
    assert failed.state is AiCallState.FAILED_AFTER_PROVIDER
    assert failed.usage_status is UsageStatus.KNOWN
    assert failed.total_tokens == 200


def test_same_attempt_concurrent_late_results_have_one_terminal_winner(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path, lease_seconds=10)
    acquired = dispatch(repository, user_id, analysis_id, body)
    repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(seconds=11),
    )

    def late_success():
        return complete(
            repository,
            user_id,
            analysis_id,
            acquired.record.attempt_id,
            body,
            now=NOW + timedelta(seconds=12),
        )

    def late_failure():
        return repository.complete_failure(
            user_id=user_id,
            analysis_id=analysis_id,
            attempt_id=acquired.record.attempt_id,
            error_code="AI_PROVIDER_RESPONSE_INVALID",
            usage=(120, 80, 200, "cuc/deepseek"),
            now=NOW + timedelta(seconds=12),
        )

    with ThreadPoolExecutor(max_workers=2) as pool:
        futures = [pool.submit(late_success), pool.submit(late_failure)]
        outcomes = []
        for future in futures:
            try:
                outcomes.append(future.result())
            except ValueError:
                outcomes.append(None)

    assert sum(outcome is not None for outcome in outcomes) == 1
    record = repository.get_for_owner(user_id=user_id, analysis_id=analysis_id)
    assert record.state in {AiCallState.SUCCEEDED, AiCallState.FAILED_AFTER_PROVIDER}
    assert record.usage_status is UsageStatus.KNOWN
    assert record.total_tokens == 200


def test_cache_is_cleared_after_24_hours_but_tombstone_blocks_replay(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = dispatch(repository, user_id, analysis_id, body)
    complete(repository, user_id, analysis_id, acquired.record.attempt_id, body)

    cleared, compacted = repository.purge_expired(now=NOW + timedelta(hours=24, seconds=1))
    replay = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(hours=25),
    )

    assert (cleared, compacted) == (1, 0)
    assert replay.kind is ReservationKind.RESULT_EXPIRED
    assert replay.record.response is None


def test_day_31_compaction_keeps_permanent_replay_tombstone(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = dispatch(repository, user_id, analysis_id, body)
    complete(repository, user_id, analysis_id, acquired.record.attempt_id, body)

    repository.purge_expired(now=NOW + timedelta(days=31))
    replay = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(days=31),
    )

    assert replay.kind is ReservationKind.RESULT_EXPIRED
    assert replay.record.response is None
    assert replay.record.total_tokens is None
    assert replay.record.model is None
    assert replay.record.compacted_at == NOW + timedelta(days=31)


def test_only_guarded_schema_valid_response_can_be_cached(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = dispatch(repository, user_id, analysis_id, body)
    invalid = provider_result()
    invalid.report["analysis_id"] = str(uuid4())

    with pytest.raises(AppError) as caught:
        complete(
            repository,
            user_id,
            analysis_id,
            acquired.record.attempt_id,
            body,
            result=invalid,
        )

    assert caught.value.code == "AI_REPORT_REJECTED"
    record = repository.get_for_owner(user_id=user_id, analysis_id=analysis_id)
    assert record.response is None
    assert record.state is AiCallState.FAILED_AFTER_PROVIDER
    assert record.usage_status is UsageStatus.KNOWN
    assert record.total_tokens == 200
    assert record.error_code == "AI_REPORT_REJECTED"


def test_sensitive_guarded_response_is_rejected_before_cache_write(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = dispatch(repository, user_id, analysis_id, body)
    unsafe = provider_result()
    unsafe.report["summary"] = "Authorization: Bearer secret-must-not-be-cached"

    with pytest.raises(UnsafeCacheResponseError):
        complete(
            repository,
            user_id,
            analysis_id,
            acquired.record.attempt_id,
            body,
            result=unsafe,
        )

    record = repository.get_for_owner(user_id=user_id, analysis_id=analysis_id)
    assert record.response is None
    assert record.state is AiCallState.FAILED_AFTER_PROVIDER
    assert record.usage_status is UsageStatus.KNOWN
    assert record.total_tokens == 200
    assert record.error_code == "AI_CACHE_RESPONSE_UNSAFE"


def test_inconsistent_provider_usage_is_rejected_before_cache_write(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = dispatch(repository, user_id, analysis_id, body)
    inconsistent = provider_result()
    inconsistent = ProviderResult(
        report=inconsistent.report,
        prompt_tokens=120,
        completion_tokens=80,
        total_tokens=201,
        model="cuc/deepseek",
    )

    with pytest.raises(ValueError, match="usage is inconsistent"):
        complete(
            repository,
            user_id,
            analysis_id,
            acquired.record.attempt_id,
            body,
            result=inconsistent,
        )

    record = repository.get_for_owner(user_id=user_id, analysis_id=analysis_id)
    assert record.response is None
    assert record.state is AiCallState.FAILED_AFTER_PROVIDER
    assert record.usage_status is UsageStatus.UNKNOWN
    assert record.error_code == "AI_PROVIDER_USAGE_INVALID"


def test_digest_rotation_accepts_records_signed_by_previous_key(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = reserve(repository, user_id, analysis_id, body)
    rotated = AiCallRepository(
        repository.database,
        digest_secrets={1: "old-local-test-secret", 2: "new-local-test-secret"},
        active_digest_key_version=2,
    )

    replay = rotated.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW,
    )

    assert acquired.record.digest_key_version == 1
    assert replay.kind is ReservationKind.IN_PROGRESS
    assert replay.record.attempt_id == acquired.record.attempt_id


def test_missing_historical_digest_key_never_reacquires_provider_slot(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path, lease_seconds=10)
    acquired = reserve(repository, user_id, analysis_id, body)
    rotated = AiCallRepository(
        repository.database,
        digest_secrets={2: "new-local-test-secret"},
        active_digest_key_version=2,
        lease_seconds=10,
    )

    replay = rotated.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW + timedelta(seconds=11),
    )

    assert replay.kind is ReservationKind.INPUT_CONFLICT
    assert replay.record.attempt_id == acquired.record.attempt_id
    assert replay.record.provider_dispatch_started_at is None


def test_cleanup_worker_runs_expiry_without_request_path(tmp_path) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    acquired = dispatch(repository, user_id, analysis_id, body)
    complete(repository, user_id, analysis_id, acquired.record.attempt_id, body)
    worker = AiCallCleanupWorker(
        repository,
        clock=lambda: NOW + timedelta(hours=25),
    )
    stop = asyncio.Event()
    stop.set()

    asyncio.run(worker.run(stop))

    record = repository.get_for_owner(user_id=user_id, analysis_id=analysis_id)
    assert record.response is None
    assert record.state is AiCallState.SUCCEEDED


def test_digest_binds_time_text_and_normalizes_array_order_and_database_has_no_secrets(
    tmp_path,
) -> None:
    repository, user_id, analysis_id, body = setup_repository(tmp_path)
    reordered = deepcopy(body)
    reordered["report_context"]["created_at"] = "2026-09-27T18:57:59.786849+08:00"
    reordered["analysis_input"]["targets"] = list(
        reversed(reordered["analysis_input"]["targets"])
    )
    reordered["hard_risk_findings"] = list(reversed(reordered["hard_risk_findings"]))

    original_time = reordered["report_context"]["created_at"]
    reordered["report_context"]["created_at"] = body["report_context"]["created_at"]
    assert repository.digest(reordered) == repository.digest(body)
    reordered["report_context"]["created_at"] = original_time
    assert repository.digest(reordered) != repository.digest(body)
    reserve(repository, user_id, analysis_id, body)

    raw = repository.database.path.read_bytes()
    for secret in (
        b"Bearer ",
        b"sk-client-secret",
        b"correct-horse",
        b"Cookie:",
        b"http://39.107.253.138/controlled/go/campus",
    ):
        assert secret not in raw


def setup_repository(tmp_path, *, lease_seconds: int = 90):
    database = Database(tmp_path / "taplens-test.db")
    database.initialize()
    user_id = create_user(database)
    repository = AiCallRepository(
        database,
        digest_secrets={1: "old-local-test-secret"},
        active_digest_key_version=1,
        lease_seconds=lease_seconds,
    )
    body = payload()
    analysis_id = UUID(body["report_context"]["analysis_id"])
    return repository, user_id, analysis_id, body


def create_user(database: Database) -> UUID:
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
    return user_id


def reserve(repository, user_id, analysis_id, body):
    return repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        payload=body,
        now=NOW,
    )


def dispatch(repository, user_id, analysis_id, body):
    acquired = reserve(repository, user_id, analysis_id, body)
    repository.mark_provider_dispatch_started(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        now=NOW,
    )
    return acquired


def complete(
    repository,
    user_id,
    analysis_id,
    attempt_id,
    body,
    *,
    result=None,
    now=NOW,
):
    return repository.complete_guarded_success(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=attempt_id,
        payload=AiAnalyzeRequest.model_validate(body),
        result=result or provider_result(),
        now=now,
    )


def provider_result() -> ProviderResult:
    return ProviderResult(
        report=json.loads(REPORT_FIXTURE.read_text(encoding="utf-8")),
        prompt_tokens=120,
        completion_tokens=80,
        total_tokens=200,
        model="cuc/deepseek",
    )


def payload() -> dict:
    return json.loads(REQUEST_FIXTURE.read_text(encoding="utf-8"))
