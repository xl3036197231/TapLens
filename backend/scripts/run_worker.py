import argparse
import asyncio
import contextlib
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

from app.core.config import get_settings
from app.sandbox.collector import DeepScanCollector, build_request_authorizer
from app.storage.database import Database
from app.storage.tasks import TaskRepository
from app.tasks.executor import TaskExecutor
from app.tasks.service import TaskService


async def run(*, once: bool, poll_seconds: float) -> None:
    settings = get_settings()
    database = Database(settings.database_path)
    database.initialize()
    repository = TaskRepository(database)
    service = TaskService(
        repository=repository,
        daily_limit=settings.daily_quota_limit,
        quota_timezone=ZoneInfo(settings.quota_timezone),
        artifact_ttl=timedelta(minutes=settings.artifact_ttl_minutes),
        allowed_test_origins=settings.allowed_test_origins,
    )
    executor = TaskExecutor(
        repository=repository,
        service=service,
        collector=DeepScanCollector(
            artifact_directory=settings.artifact_directory,
            request_authorizer=build_request_authorizer(settings.allowed_test_origins),
        ),
        public_base_url=settings.public_base_url,
    )

    while True:
        queued = repository.list_queued(limit=10)
        for task in queued:
            await executor.execute(task.id)
        now = datetime.now(UTC)
        expiring_artifacts = repository.list_due_for_expiry(now)
        service.expire_due(now)
        for task_id in expiring_artifacts:
            (settings.artifact_directory / f"{task_id}.png").unlink(missing_ok=True)
        if once:
            return
        await asyncio.sleep(poll_seconds)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run queued TapLens cloud scans")
    parser.add_argument("--once", action="store_true", help="process the current queue and exit")
    parser.add_argument("--poll-seconds", type=float, default=1.0)
    return parser.parse_args()


if __name__ == "__main__":
    arguments = parse_args()
    with contextlib.suppress(KeyboardInterrupt):
        asyncio.run(run(once=arguments.once, poll_seconds=max(0.1, arguments.poll_seconds)))
