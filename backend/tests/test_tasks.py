from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

import pytest

from app.auth.passwords import PasswordService
from app.core.errors import AppError
from app.storage.database import Database
from app.storage.tasks import TaskRepository
from app.storage.users import UserRecord, UserRepository
from app.tasks.models import TaskStatus
from app.tasks.service import TaskService


NOW = datetime(2026, 9, 21, 2, 0, tzinfo=UTC)


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

    valid = service.create(
        user_id=user_id,
        analysis_id=uuid4(),
        target_url="https://8.8.8.8/public",
        now=NOW,
    )
    assert captured.value.code == "CLOUD_PRIVATE_ADDRESS_BLOCKED"
    assert valid.status == TaskStatus.QUEUED


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


def build_service(tmp_path, daily_limit: int = 10):
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
    )
    return service, repository, user_id
