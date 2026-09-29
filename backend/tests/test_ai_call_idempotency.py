import json
from concurrent.futures import ThreadPoolExecutor
from copy import deepcopy
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

from app.storage.ai_calls import (
    AiCallRepository,
    AiCallState,
    ReservationKind,
    UsageStatus,
)
from app.storage.database import Database


ROOT = Path(__file__).resolve().parents[2]
REQUEST_FIXTURE = ROOT / "shared/fixtures/ai/day5-school-model-request.json"
NOW = datetime(2026, 9, 29, 12, 0, tzinfo=UTC)


def test_concurrent_same_analysis_acquires_one_provider_slot(tmp_path) -> None:
    repository, user_id, analysis_id, digest = setup_repository(tmp_path)

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(
            pool.map(
                lambda _: repository.reserve(
                    user_id=user_id,
                    analysis_id=analysis_id,
                    input_digest=digest,
                    now=NOW,
                ),
                range(2),
            )
        )

    assert sorted(result.kind for result in results) == sorted(
        [ReservationKind.ACQUIRED, ReservationKind.IN_PROGRESS]
    )
    assert len({result.record.attempt_id for result in results}) == 1


def test_successful_result_is_cached_without_new_attempt(tmp_path) -> None:
    repository, user_id, analysis_id, digest = setup_repository(tmp_path)
    acquired = reserve(repository, user_id, analysis_id, digest)
    repository.mark_provider_dispatch_started(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        now=NOW,
    )
    expected = {"analysis_id": str(analysis_id), "report": {"sources": {"ai": True}}}
    repository.complete_success(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        response=expected,
        prompt_tokens=10,
        completion_tokens=5,
        total_tokens=15,
        model="cuc/deepseek",
        now=NOW,
    )

    replay = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        input_digest=digest,
        now=NOW + timedelta(hours=1),
    )

    assert replay.kind is ReservationKind.CACHED
    assert replay.record.response == expected
    assert replay.record.usage_status is UsageStatus.KNOWN
    assert replay.record.total_tokens == 15
    assert replay.record.attempt_id == acquired.record.attempt_id


def test_same_analysis_with_different_input_is_conflict(tmp_path) -> None:
    repository, user_id, analysis_id, digest = setup_repository(tmp_path)
    reserve(repository, user_id, analysis_id, digest)

    conflict = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        input_digest="0" * 64,
        now=NOW,
    )

    assert conflict.kind is ReservationKind.INPUT_CONFLICT
    with repository.database.connect() as connection:
        count = connection.execute(
            "SELECT COUNT(*) FROM ai_analysis_calls WHERE user_id = ? AND analysis_id = ?",
            (str(user_id), str(analysis_id)),
        ).fetchone()[0]
    assert count == 1


def test_same_analysis_is_isolated_between_users(tmp_path) -> None:
    repository, first_user, analysis_id, digest = setup_repository(tmp_path)
    second_user = create_user(repository.database)

    first = reserve(repository, first_user, analysis_id, digest)
    second = reserve(repository, second_user, analysis_id, digest)

    assert first.kind is ReservationKind.ACQUIRED
    assert second.kind is ReservationKind.ACQUIRED
    assert first.record.attempt_id != second.record.attempt_id


def test_guard_rejection_after_dispatch_is_terminal_and_keeps_known_usage(tmp_path) -> None:
    repository, user_id, analysis_id, digest = setup_repository(tmp_path)
    acquired = reserve(repository, user_id, analysis_id, digest)
    repository.mark_provider_dispatch_started(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        now=NOW,
    )
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
        input_digest=digest,
        now=NOW + timedelta(minutes=1),
    )

    assert failed.state is AiCallState.FAILED_AFTER_PROVIDER
    assert failed.usage_status is UsageStatus.KNOWN
    assert failed.total_tokens == 200
    assert replay.kind is ReservationKind.TERMINAL_FAILURE
    assert replay.record.attempt_id == acquired.record.attempt_id


def test_expired_dispatched_lease_becomes_unknown_and_never_reacquires(tmp_path) -> None:
    repository, user_id, analysis_id, digest = setup_repository(tmp_path, lease_seconds=10)
    acquired = reserve(repository, user_id, analysis_id, digest)
    repository.mark_provider_dispatch_started(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        now=NOW,
    )

    first_replay = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        input_digest=digest,
        now=NOW + timedelta(seconds=11),
    )
    second_replay = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        input_digest=digest,
        now=NOW + timedelta(days=1),
    )

    assert first_replay.kind is ReservationKind.OUTCOME_UNKNOWN
    assert first_replay.record.state is AiCallState.OUTCOME_UNKNOWN
    assert first_replay.record.error_code == "AI_OUTCOME_UNKNOWN"
    assert first_replay.record.retryable is False
    assert second_replay.kind is ReservationKind.OUTCOME_UNKNOWN
    assert second_replay.record.attempt_id == acquired.record.attempt_id


def test_expired_undispatched_lease_is_the_only_safe_reacquire(tmp_path) -> None:
    repository, user_id, analysis_id, digest = setup_repository(tmp_path, lease_seconds=10)
    acquired = reserve(repository, user_id, analysis_id, digest)

    retry = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        input_digest=digest,
        now=NOW + timedelta(seconds=11),
    )

    assert retry.kind is ReservationKind.ACQUIRED
    assert retry.record.attempt_id != acquired.record.attempt_id
    assert retry.record.provider_dispatch_started_at is None


def test_cache_is_cleared_after_24_hours_but_tombstone_blocks_replay(tmp_path) -> None:
    repository, user_id, analysis_id, digest = setup_repository(tmp_path)
    acquired = reserve(repository, user_id, analysis_id, digest)
    repository.mark_provider_dispatch_started(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        now=NOW,
    )
    repository.complete_success(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        response={"guarded": True},
        prompt_tokens=1,
        completion_tokens=1,
        total_tokens=2,
        model="cuc/deepseek",
        now=NOW,
    )

    cleared, deleted = repository.purge_expired(now=NOW + timedelta(hours=24, seconds=1))
    replay = repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        input_digest=digest,
        now=NOW + timedelta(hours=25),
    )

    assert (cleared, deleted) == (1, 0)
    assert replay.kind is ReservationKind.RESULT_EXPIRED
    assert replay.record.response is None
    assert replay.record.state is AiCallState.SUCCEEDED


def test_tombstone_is_deleted_after_30_days(tmp_path) -> None:
    repository, user_id, analysis_id, digest = setup_repository(tmp_path)
    acquired = reserve(repository, user_id, analysis_id, digest)
    repository.complete_failure(
        user_id=user_id,
        analysis_id=analysis_id,
        attempt_id=acquired.record.attempt_id,
        error_code="AI_LOCAL_PRECHECK_FAILED",
        now=NOW,
    )

    _, deleted = repository.purge_expired(now=NOW + timedelta(days=30, seconds=1))

    assert deleted == 1
    assert repository.get_for_owner(user_id=user_id, analysis_id=analysis_id) is None


def test_digest_ignores_volatile_time_and_array_order_and_database_has_no_secrets(tmp_path) -> None:
    repository, user_id, analysis_id, _ = setup_repository(tmp_path)
    original = payload()
    reordered = deepcopy(original)
    reordered["report_context"]["created_at"] = "2030-01-01T00:00:00Z"
    reordered["analysis_input"]["targets"] = list(
        reversed(reordered["analysis_input"]["targets"])
    )
    reordered["hard_risk_findings"] = list(reversed(reordered["hard_risk_findings"]))

    digest = repository.digest(original)
    assert repository.digest(reordered) == digest
    reserve(repository, user_id, analysis_id, digest)

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
        digest_secret="local-test-hmac-secret",
        lease_seconds=lease_seconds,
    )
    body = payload()
    analysis_id = UUID(body["report_context"]["analysis_id"])
    return repository, user_id, analysis_id, repository.digest(body)


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


def reserve(repository, user_id, analysis_id, digest):
    return repository.reserve(
        user_id=user_id,
        analysis_id=analysis_id,
        input_digest=digest,
        now=NOW,
    )


def payload() -> dict:
    return json.loads(REQUEST_FIXTURE.read_text(encoding="utf-8"))
