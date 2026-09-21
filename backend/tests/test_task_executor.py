import asyncio
import json
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource

from app.auth.passwords import PasswordService
from app.sandbox.collector import CollectorError, CollectorResult
from app.storage.database import Database
from app.storage.tasks import TaskRepository
from app.storage.users import UserRecord, UserRepository
from app.tasks.executor import TaskExecutor
from app.tasks.models import TaskStatus
from app.tasks.service import TaskService


NOW = datetime(2026, 9, 21, 2, 0, tzinfo=UTC)
SCHEMA_PATH = Path(__file__).resolve().parents[2] / "shared/contracts/cloud-evidence.schema.json"
COMMON_SCHEMA_PATH = Path(__file__).resolve().parents[2] / "shared/contracts/common.schema.json"


class SuccessfulCollector:
    async def collect(self, *, task_id: str, target_url: str) -> CollectorResult:
        return CollectorResult(
            final_url="https://final.example/result",
            title="Demo",
            text_summary="A safely collected page summary.",
            redirects=[],
            requests=[{
                "origin": "https://final.example",
                "method": "GET",
                "resource_type": "document",
                "status_code": 200,
            }],
            forms=[{
                "action": "https://final.example/submit",
                "method": "POST",
                "fields": [{"name": "phone", "type": "tel", "sensitive": True}],
            }],
            blocked_actions=[],
            screenshot_path=Path(f"/tmp/{task_id}.png"),
            limitations=[],
        )


class FailingCollector:
    async def collect(self, *, task_id: str, target_url: str) -> CollectorResult:
        raise CollectorError("CLOUD_TASK_TIMEOUT", "云端页面加载超时")


def test_executor_builds_schema_valid_success_evidence(tmp_path) -> None:
    executor, repository, task_id = build_executor(tmp_path, SuccessfulCollector())

    assert asyncio.run(executor.execute(task_id)) is True

    task = repository.get(task_id)
    assert task is not None
    assert task.status == TaskStatus.SUCCEEDED
    assert task.target_url is None
    assert task.evidence is not None
    assert task.evidence["screenshot"]["download_url"].endswith(f"/{task_id}/screenshot")
    validate_cloud_evidence(task.evidence)


def test_executor_builds_schema_valid_failure_evidence(tmp_path) -> None:
    executor, repository, task_id = build_executor(tmp_path, FailingCollector())

    assert asyncio.run(executor.execute(task_id)) is True

    task = repository.get(task_id)
    assert task is not None
    assert task.status == TaskStatus.FAILED
    assert task.error_code == "CLOUD_TASK_TIMEOUT"
    assert task.target_url is None
    assert task.evidence is not None
    assert task.evidence["error"]["retryable"] is True
    validate_cloud_evidence(task.evidence)


def test_executor_does_not_run_terminal_task_twice(tmp_path) -> None:
    executor, repository, task_id = build_executor(tmp_path, SuccessfulCollector())
    assert asyncio.run(executor.execute(task_id)) is True

    assert asyncio.run(executor.execute(task_id)) is False
    assert repository.get(task_id).status == TaskStatus.SUCCEEDED


def build_executor(tmp_path, collector):
    database = Database(tmp_path / "taplens-executor-test.db")
    database.initialize()
    user_id = UUID("de2f28e6-f6ca-4c8f-8c0e-111871dc0002")
    UserRepository(database).create(
        UserRecord(
            id=user_id,
            username="Executor_User",
            username_normalized="executor_user",
            password_hash=PasswordService().hash("correct-horse"),
            created_at=NOW,
        )
    )
    repository = TaskRepository(database)
    service = TaskService(
        repository=repository,
        daily_limit=10,
        quota_timezone=ZoneInfo("Asia/Shanghai"),
    )
    task = service.create(
        user_id=user_id,
        analysis_id=uuid4(),
        target_url="https://8.8.8.8/start?secret=removed",
        now=NOW,
    )
    return (
        TaskExecutor(
            repository=repository,
            service=service,
            collector=collector,
            public_base_url="https://api.example",
        ),
        repository,
        task.id,
    )


def validate_cloud_evidence(document: dict[str, object]) -> None:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    common_schema = json.loads(COMMON_SCHEMA_PATH.read_text(encoding="utf-8"))
    registry = Registry().with_resource(
        common_schema["$id"],
        Resource.from_contents(common_schema),
    )
    errors = list(
        Draft202012Validator(
            schema,
            registry=registry,
            format_checker=FormatChecker(),
        ).iter_errors(document)
    )
    assert errors == [], "\n".join(error.message for error in errors)
