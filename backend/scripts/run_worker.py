import argparse
import asyncio
import contextlib
from datetime import UTC, datetime, timedelta
from zoneinfo import ZoneInfo

from app.core.config import get_settings
from app.sandbox.collector import DeepScanCollector, build_request_authorizer
from app.sandbox.fictional_fixture import DEFAULT_FIXTURE_BASE_URL
from app.storage.database import Database
from app.storage.tasks import TaskRepository
from app.tasks.executor import TaskExecutor
from app.tasks.service import TaskService
from app.qr_analysis.catalog import QrFixtureCatalog
from app.qr_analysis.executor import QrAnalysisExecutor
from app.qr_analysis.fake_provider import (
    build_qr_analysis_provider,
    expire_qr_fake_results,
)
from app.storage.qr_analyses import QrAnalysisRepository


async def run(*, once: bool, poll_seconds: float) -> None:
    settings = get_settings()
    database = Database(settings.database_path)
    database.initialize()
    repository = TaskRepository(database)
    fixture_base_url = DEFAULT_FIXTURE_BASE_URL
    if settings.environment in {"development", "test"} and settings.allowed_test_origins:
        # Codespaces and local development serve the controlled page directly
        # on this exact test-only origin instead of through the compose nginx.
        fixture_base_url = settings.allowed_test_origins[0]
    service = TaskService(
        repository=repository,
        daily_limit=settings.daily_quota_limit,
        quota_timezone=ZoneInfo(settings.quota_timezone),
        digest_secrets=settings.ai_digest_secret_map,
        active_digest_key_version=settings.ai_digest_active_key_version,
        artifact_ttl=timedelta(minutes=settings.artifact_ttl_minutes),
        allowed_test_origins=settings.allowed_test_origins,
    )
    executor = TaskExecutor(
        repository=repository,
        service=service,
        collector=DeepScanCollector(
            artifact_directory=settings.artifact_directory,
            request_authorizer=build_request_authorizer(settings.allowed_test_origins),
            fictional_fixture_base_url=fixture_base_url,
        ),
        public_base_url=settings.public_base_url,
    )
    qr_repository = QrAnalysisRepository(
        database,
        digest_secrets=settings.ai_digest_secret_map,
        active_digest_key_version=settings.ai_digest_active_key_version,
        cache_hours=settings.ai_response_cache_hours,
        compact_days=settings.ai_compact_days,
    )
    qr_executor = QrAnalysisExecutor(
        qr_repository,
        QrFixtureCatalog(),
        build_qr_analysis_provider(settings),
    )
    repository.requeue_running()
    qr_repository.recover_interrupted()

    while True:
        queued = repository.list_queued(limit=10)
        for task in queued:
            await executor.execute(task.id)
        qr_queued = qr_repository.list_queued(limit=10)
        for task in qr_queued:
            await qr_executor.execute(task.task_id)
        expire_qr_fake_results(qr_repository, settings)
        now = datetime.now(UTC)
        expiring_artifacts = repository.list_due_for_expiry(now)
        service.expire_due(now)
        qr_repository.cleanup(now)
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
