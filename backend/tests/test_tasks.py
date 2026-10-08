from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

import pytest

from app.auth.passwords import PasswordService
from app.core.errors import AppError
from app.storage.database import Database
from app.storage.quota import QuotaRepository
from app.storage.tasks import TaskRepository
from app.storage.users import UserRecord, UserRepository
from app.tasks.models import TaskStatus
from app.tasks.service import TaskService


NOW = datetime(2026, 9, 21, 2, 0, tzinfo=UTC)
TEST_DIGEST_SECRETS = {1: "test-cloud-task-digest-secret"}


def test_task_lifecycle_clears_target_and_expires_evidence(tmp_path) -> None:
    service, repository, user_id = build_service(tmp_path)
    task = service.create(
        user_id=user_id,
        analysis_id=uuid4(),
        target_url="https://8.8.8.8/example",
        now=NOW,
    )

    running = service.start(task.id, now=NOW + timedelta(seconds=1))
    succeeded = service.succeed(
        task.id,
        evidence={"status": "succeeded", "evidence": [{"id": "C01"}]},
        duration_ms=2500,
        now=NOW + timedelta(seconds=3),
    )

    assert running.status == TaskStatus.RUNNING
    assert succeeded.status == TaskStatus.SUCCEEDED
    assert succeeded.target_url is None
    assert succeeded.evidence == {"status": "succeeded", "evidence": [{"id": "C01"}]}
    assert succeeded.expires_at == NOW + timedelta(minutes=30, seconds=3)
    assert service.expire_due(NOW + timedelta(minutes=31)) == 1
    expired = repository.get(task.id)
    assert expired is not None
    assert expired.status == TaskStatus.EXPIRED
    assert expired.evidence is None


def test_task_creation_and_quota_consumption_are_atomic(tmp_path) -> None:
    service, repository, user_id = build_service(tmp_path, daily_limit=1)
    first = service.create(
        user_id=user_id,
        analysis_id=uuid4(),
        target_url="https://8.8.8.8/first",
        now=NOW,
    )

    with pytest.raises(AppError) as captured:
        service.create(
            user_id=user_id,
            analysis_id=uuid4(),
            target_url="https://1.1.1.1/second",
            now=NOW,
        )

    assert first.status == TaskStatus.QUEUED
    assert captured.value.code == "QUOTA_EXHAUSTED"
    assert repository.get(first.id) is not None


def test_invalid_target_does_not_consume_quota(tmp_path) -> None:
    service, _, user_id = build_service(tmp_path, daily_limit=1)

    with pytest.raises(AppError) as captured:
        service.create(
            user_id=user_id,
            analysis_id=uuid4(),
            target_url="http://127.0.0.1/private",
            now=NOW,
        )

    quota_date = NOW.astimezone(ZoneInfo("Asia/Shanghai")).date()
    assert QuotaRepository(service.repository.database).used(user_id, quota_date) == 0
    valid = service.create(
        user_id=user_id,
        analysis_id=uuid4(),
        target_url="https://8.8.8.8/public",
        now=NOW,
    )
    assert captured.value.code == "CLOUD_PRIVATE_ADDRESS_BLOCKED"
    assert valid.status == TaskStatus.QUEUED


def test_exact_test_origin_can_create_task_without_relaxing_other_ports(tmp_path) -> None:
    allowed_origin = "http://127.0.0.1:8765"
    service, _, user_id = build_service(
        tmp_path,
        allowed_test_origins=(allowed_origin,),
    )

    created = service.create(
        user_id=user_id,
        analysis_id=uuid4(),
        target_url=f"{allowed_origin}/go/campus",
        now=NOW,
    )

    assert created.status == TaskStatus.QUEUED
    with pytest.raises(AppError) as captured:
        service.create(
            user_id=user_id,
            analysis_id=uuid4(),
            target_url="http://127.0.0.1:8766/go/campus",
            now=NOW,
        )
    assert captured.value.code == "CLOUD_PRIVATE_ADDRESS_BLOCKED"


def test_dns_validation_failure_does_not_consume_quota(tmp_path, monkeypatch) -> None:
    service, _, user_id = build_service(tmp_path, daily_limit=1)

    def reject_dns(_, **__):
        from app.sandbox.url_policy import UnsafeTargetError

        raise UnsafeTargetError("CLOUD_PRIVATE_ADDRESS_BLOCKED", "DNS解析到私网地址")

    monkeypatch.setattr("app.tasks.service.resolve_and_validate_target", reject_dns)
    with pytest.raises(AppError) as captured:
        service.create(
            user_id=user_id,
            analysis_id=uuid4(),
            target_url="https://public.example/path",
            now=NOW,
        )

    assert captured.value.code == "CLOUD_PRIVATE_ADDRESS_BLOCKED"
    quota_date = NOW.astimezone(ZoneInfo("Asia/Shanghai")).date()
    assert QuotaRepository(service.repository.database).used(user_id, quota_date) == 0


def test_exact_fictional_fixture_skips_dns_and_creates_task(tmp_path, monkeypatch) -> None:
    service, _, user_id = build_service(tmp_path, daily_limit=1)

    def reject_dns(*_, **__):
        raise AssertionError("known fictional fixtures must map before DNS lookup")

    monkeypatch.setattr("app.tasks.service.resolve_and_validate_target", reject_dns)
    task = service.create(
        user_id=user_id,
        analysis_id=uuid4(),
        target_url="https://campus.example.test/go/campus",
        now=NOW,
    )

    quota_date = NOW.astimezone(ZoneInfo("Asia/Shanghai")).date()
    assert task.status == TaskStatus.QUEUED
    assert task.target_url == "https://campus.example.test/go/campus"
    assert QuotaRepository(service.repository.database).used(user_id, quota_date) == 1


def test_same_cloud_request_replays_one_task_and_consumes_quota_once(tmp_path) -> None:
    service, _, user_id = build_service(tmp_path, daily_limit=2)
    analysis_id = uuid4()

    first = service.create(
        user_id=user_id,
        analysis_id=analysis_id,
        target_url="https://8.8.8.8/example",
        now=NOW,
    )
    replay = service.create(
        user_id=user_id,
        analysis_id=analysis_id,
        target_url="https://8.8.8.8/example",
        now=NOW + timedelta(seconds=1),
    )

    quota_date = NOW.astimezone(ZoneInfo("Asia/Shanghai")).date()
    assert replay.id == first.id
    assert QuotaRepository(service.repository.database).used(user_id, quota_date) == 1


def test_same_analysis_id_with_different_cloud_input_is_conflict(tmp_path) -> None:
    service, _, user_id = build_service(tmp_path, daily_limit=2)
    analysis_id = uuid4()
    service.create(
        user_id=user_id,
        analysis_id=analysis_id,
        target_url="https://8.8.8.8/first",
        now=NOW,
    )

    with pytest.raises(AppError) as captured:
        service.create(
            user_id=user_id,
            analysis_id=analysis_id,
            target_url="https://8.8.8.8/changed",
            now=NOW + timedelta(seconds=1),
        )

    quota_date = NOW.astimezone(ZoneInfo("Asia/Shanghai")).date()
    assert captured.value.code == "CLOUD_ANALYSIS_INPUT_CONFLICT"
    assert QuotaRepository(service.repository.database).used(user_id, quota_date) == 1


def test_concurrent_cloud_request_creates_one_task_and_charges_once(tmp_path) -> None:
    service, repository, user_id = build_service(tmp_path, daily_limit=2)
    analysis_id = uuid4()

    def create():
        return service.create(
            user_id=user_id,
            analysis_id=analysis_id,
            target_url="https://8.8.8.8/concurrent",
            now=NOW,
        )

    with ThreadPoolExecutor(max_workers=8) as pool:
        tasks = list(pool.map(lambda _: create(), range(8)))

    quota_date = NOW.astimezone(ZoneInfo("Asia/Shanghai")).date()
    assert len({task.id for task in tasks}) == 1
    assert repository.get(tasks[0].id) is not None
    assert QuotaRepository(service.repository.database).used(user_id, quota_date) == 1


def test_deleted_task_keeps_replay_tombstone_and_cannot_charge_again(tmp_path) -> None:
    service, _, user_id = build_service(tmp_path, daily_limit=2)
    analysis_id = uuid4()
    task = service.create(
        user_id=user_id,
        analysis_id=analysis_id,
        target_url="https://8.8.8.8/deleted",
        now=NOW,
    )
    assert service.delete_for_owner(task.id, user_id) is True

    with pytest.raises(AppError) as captured:
        service.create(
            user_id=user_id,
            analysis_id=analysis_id,
            target_url="https://8.8.8.8/deleted",
            now=NOW + timedelta(seconds=1),
        )

    quota_date = NOW.astimezone(ZoneInfo("Asia/Shanghai")).date()
    with service.repository.database.connect() as connection:
        tombstone = connection.execute(
            """
            SELECT task_id, target_digest, digest_key_version
            FROM cloud_scan_requests
            WHERE user_id = ? AND analysis_id = ?
            """,
            (str(user_id), str(analysis_id)),
        ).fetchone()
    assert captured.value.code == "CLOUD_TASK_RESULT_EXPIRED"
    assert QuotaRepository(service.repository.database).used(user_id, quota_date) == 1
    assert tombstone["task_id"] == str(task.id)
    assert len(tombstone["target_digest"]) == 64
    assert "deleted" not in "".join(str(value) for value in tombstone)


def test_expired_task_keeps_replay_tombstone_and_cannot_charge_again(tmp_path) -> None:
    service, _, user_id = build_service(tmp_path, daily_limit=2)
    analysis_id = uuid4()
    task = service.create(
        user_id=user_id,
        analysis_id=analysis_id,
        target_url="https://8.8.8.8/expired",
        now=NOW,
    )
    service.start(task.id, now=NOW + timedelta(seconds=1))
    service.succeed(
        task.id,
        evidence={"status": "succeeded"},
        duration_ms=10,
        now=NOW + timedelta(seconds=2),
    )
    assert service.expire_due(NOW + timedelta(minutes=31)) == 1

    with pytest.raises(AppError) as captured:
        service.create(
            user_id=user_id,
            analysis_id=analysis_id,
            target_url="https://8.8.8.8/expired",
            now=NOW + timedelta(minutes=32),
        )

    quota_date = NOW.astimezone(ZoneInfo("Asia/Shanghai")).date()
    assert captured.value.code == "CLOUD_TASK_RESULT_EXPIRED"
    assert QuotaRepository(service.repository.database).used(user_id, quota_date) == 1


def test_legacy_task_is_tombstoned_before_conflict(tmp_path) -> None:
    service, repository, user_id = build_service(tmp_path, daily_limit=2)
    analysis_id = uuid4()
    legacy_id = uuid4()
    with repository.database.connect() as connection:
        connection.execute(
            """
            INSERT INTO cloud_scan_tasks (
                id, user_id, analysis_id, status, target_url, evidence_json,
                error_code, created_at, started_at, completed_at, expires_at,
                duration_ms
            ) VALUES (?, ?, ?, 'queued', ?, NULL, NULL, ?, NULL, NULL, NULL, NULL)
            """,
            (
                str(legacy_id),
                str(user_id),
                str(analysis_id),
                "https://8.8.8.8/legacy",
                NOW.isoformat(),
            ),
        )

    with pytest.raises(AppError) as captured:
        service.create(
            user_id=user_id,
            analysis_id=analysis_id,
            target_url="https://8.8.8.8/legacy",
            now=NOW + timedelta(seconds=1),
        )

    with repository.database.connect() as connection:
        reservation = connection.execute(
            """
            SELECT task_id, target_digest
            FROM cloud_scan_requests
            WHERE user_id = ? AND analysis_id = ?
            """,
            (str(user_id), str(analysis_id)),
        ).fetchone()
    assert captured.value.code == "CLOUD_ANALYSIS_INPUT_CONFLICT"
    assert reservation["task_id"] == str(legacy_id)
    assert reservation["target_digest"] is None


def test_cloud_request_replays_across_digest_key_rotation(tmp_path) -> None:
    service, repository, user_id = build_service(
        tmp_path,
        daily_limit=2,
        digest_secrets={1: "old-task-digest", 2: "new-task-digest"},
        active_digest_key_version=1,
    )
    analysis_id = uuid4()
    first = service.create(
        user_id=user_id,
        analysis_id=analysis_id,
        target_url="https://8.8.8.8/rotation",
        now=NOW,
    )
    rotated = TaskService(
        repository=repository,
        daily_limit=2,
        quota_timezone=ZoneInfo("Asia/Shanghai"),
        digest_secrets={1: "old-task-digest", 2: "new-task-digest"},
        active_digest_key_version=2,
    )

    replay = rotated.create(
        user_id=user_id,
        analysis_id=analysis_id,
        target_url="https://8.8.8.8/rotation",
        now=NOW + timedelta(seconds=1),
    )

    assert replay.id == first.id


def test_missing_historical_cloud_digest_key_fails_closed(tmp_path) -> None:
    service, repository, user_id = build_service(
        tmp_path,
        daily_limit=2,
        digest_secrets={1: "old-task-digest"},
        active_digest_key_version=1,
    )
    analysis_id = uuid4()
    service.create(
        user_id=user_id,
        analysis_id=analysis_id,
        target_url="https://8.8.8.8/rotation",
        now=NOW,
    )
    without_old_key = TaskService(
        repository=repository,
        daily_limit=2,
        quota_timezone=ZoneInfo("Asia/Shanghai"),
        digest_secrets={2: "new-task-digest"},
        active_digest_key_version=2,
    )

    with pytest.raises(AppError) as captured:
        without_old_key.create(
            user_id=user_id,
            analysis_id=analysis_id,
            target_url="https://8.8.8.8/rotation",
            now=NOW + timedelta(seconds=1),
        )

    assert captured.value.code == "CLOUD_ANALYSIS_INPUT_CONFLICT"


def test_unknown_fictional_host_still_requires_dns_before_quota(tmp_path, monkeypatch) -> None:
    service, _, user_id = build_service(tmp_path, daily_limit=1)

    def reject_dns(_, **__):
        from app.sandbox.url_policy import UnsafeTargetError

        raise UnsafeTargetError("CLOUD_PRIVATE_ADDRESS_BLOCKED", "DNS解析失败")

    monkeypatch.setattr("app.tasks.service.resolve_and_validate_target", reject_dns)
    with pytest.raises(AppError) as captured:
        service.create(
            user_id=user_id,
            analysis_id=uuid4(),
            target_url="https://not-listed.example.test/apply",
            now=NOW,
        )

    quota_date = NOW.astimezone(ZoneInfo("Asia/Shanghai")).date()
    assert captured.value.code == "CLOUD_PRIVATE_ADDRESS_BLOCKED"
    assert QuotaRepository(service.repository.database).used(user_id, quota_date) == 0


def test_invalid_transition_is_rejected(tmp_path) -> None:
    service, _, user_id = build_service(tmp_path)
    task = service.create(
        user_id=user_id,
        analysis_id=uuid4(),
        target_url="https://8.8.8.8/example",
        now=NOW,
    )

    with pytest.raises(AppError) as captured:
        service.succeed(task.id, evidence={}, duration_ms=1, now=NOW)

    assert captured.value.code == "CLOUD_TASK_INVALID_STATE"


def test_running_task_is_requeued_after_worker_restart(tmp_path) -> None:
    service, repository, user_id = build_service(tmp_path)
    task = service.create(
        user_id=user_id,
        analysis_id=uuid4(),
        target_url="https://8.8.8.8/example",
        now=NOW,
    )
    service.start(task.id, now=NOW + timedelta(seconds=1))

    assert repository.requeue_running() == 1
    recovered = repository.get(task.id)

    assert recovered is not None
    assert recovered.status == TaskStatus.QUEUED
    assert recovered.started_at is None
    assert recovered.target_url == "https://8.8.8.8/example"


def test_task_owner_cannot_read_another_users_task(tmp_path) -> None:
    service, _, user_id = build_service(tmp_path)
    task = service.create(
        user_id=user_id,
        analysis_id=uuid4(),
        target_url="https://8.8.8.8/example",
        now=NOW,
    )

    with pytest.raises(AppError) as captured:
        service.get_for_owner(task.id, uuid4())

    assert captured.value.code == "CLOUD_TASK_NOT_FOUND"


def build_service(
    tmp_path,
    daily_limit: int = 10,
    allowed_test_origins: tuple[str, ...] = (),
    digest_secrets: dict[int, str] | None = None,
    active_digest_key_version: int = 1,
):
    database = Database(tmp_path / "taplens-tasks-test.db")
    database.initialize()
    user_id = UUID("de2f28e6-f6ca-4c8f-8c0e-111871dc0001")
    UserRepository(database).create(
        UserRecord(
            id=user_id,
            username="Task_User",
            username_normalized="task_user",
            password_hash=PasswordService().hash("correct-horse"),
            created_at=NOW,
        )
    )
    repository = TaskRepository(database)
    service = TaskService(
        repository=repository,
        daily_limit=daily_limit,
        quota_timezone=ZoneInfo("Asia/Shanghai"),
        allowed_test_origins=allowed_test_origins,
        digest_secrets=digest_secrets or TEST_DIGEST_SECRETS,
        active_digest_key_version=active_digest_key_version,
    )
    return service, repository, user_id
