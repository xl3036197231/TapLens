import time
from datetime import UTC, datetime
from typing import Protocol
from uuid import UUID

from app.core.errors import AppError
from app.sandbox.collector import CollectorError, CollectorResult
from app.storage.tasks import TaskRepository
from app.tasks.evidence import build_failure_evidence, build_success_evidence
from app.tasks.models import CloudScanTask
from app.tasks.service import TaskService


class Collector(Protocol):
    async def collect(self, *, task_id: str, target_url: str) -> CollectorResult: ...


class TaskExecutor:
    def __init__(
        self,
        *,
        repository: TaskRepository,
        service: TaskService,
        collector: Collector,
        public_base_url: str,
    ) -> None:
        self.repository = repository
        self.service = service
        self.collector = collector
        self.public_base_url = public_base_url

    async def execute(self, task_id: UUID) -> bool:
        queued = self.repository.get(task_id)
        if queued is None or queued.target_url is None:
            return False
        try:
            self.service.start(task_id)
        except AppError as exc:
            if exc.code == "CLOUD_TASK_INVALID_STATE":
                return False
            raise

        started = time.monotonic()
        try:
            result = await self.collector.collect(
                task_id=str(task_id),
                target_url=queued.target_url,
            )
        except CollectorError as exc:
            await self._fail(
                queued=queued,
                started=started,
                error_code=exc.code,
                message=exc.message,
                retryable=exc.code in {"CLOUD_TASK_TIMEOUT", "CLOUD_BROWSER_ERROR"},
            )
            return True
        except Exception:
            await self._fail(
                queued=queued,
                started=started,
                error_code="CLOUD_BROWSER_ERROR",
                message="云端浏览器分析失败",
                retryable=True,
            )
            return True

        completed_at = datetime.now(UTC)
        duration_ms = elapsed_ms(started)
        expires_at = completed_at + self.service.artifact_ttl
        try:
            evidence = build_success_evidence(
                analysis_id=queued.analysis_id,
                task_id=queued.id,
                initial_url=queued.target_url,
                result=result,
                generated_at=completed_at,
                expires_at=expires_at,
                duration_ms=duration_ms,
                public_base_url=self.public_base_url,
            )
        except Exception:
            await self._fail(
                queued=queued,
                started=started,
                error_code="CLOUD_EVIDENCE_BUILD_FAILED",
                message="云端证据组装失败",
                retryable=True,
            )
            return True
        self.service.succeed(
            task_id,
            evidence=evidence,
            duration_ms=duration_ms,
            now=completed_at,
        )
        return True

    async def _fail(
        self,
        *,
        queued: CloudScanTask,
        started: float,
        error_code: str,
        message: str,
        retryable: bool,
    ) -> None:
        completed_at = datetime.now(UTC)
        duration_ms = elapsed_ms(started)
        expires_at = completed_at + self.service.artifact_ttl
        evidence = build_failure_evidence(
            analysis_id=queued.analysis_id,
            task_id=queued.id,
            initial_url=queued.target_url,
            generated_at=completed_at,
            expires_at=expires_at,
            duration_ms=duration_ms,
            error_code=error_code,
            message=message,
            retryable=retryable,
        )
        self.service.fail(
            queued.id,
            error_code=error_code,
            evidence=evidence,
            duration_ms=duration_ms,
            now=completed_at,
        )


def elapsed_ms(started: float) -> int:
    return max(0, round((time.monotonic() - started) * 1000))
