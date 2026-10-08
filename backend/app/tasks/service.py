import hashlib
import hmac
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

from app.core.errors import AppError
from app.sandbox.fictional_fixture import fixture_for_url
from app.sandbox.url_policy import (
    UnsafeTargetError,
    resolve_and_validate_target,
    validate_target_url,
)
from app.storage.tasks import (
    InvalidTaskTransitionError,
    QuotaExceededError,
    TaskInputConflictError,
    TaskNotFoundError,
    TaskRepository,
    TaskResultExpiredError,
)
from app.tasks.models import CloudScanTask, TaskStatus


class TaskService:
    def __init__(
        self,
        *,
        repository: TaskRepository,
        daily_limit: int,
        quota_timezone: ZoneInfo,
        digest_secrets: dict[int, str],
        artifact_ttl: timedelta = timedelta(minutes=30),
        allowed_test_origins: tuple[str, ...] = (),
        active_digest_key_version: int = 1,
    ) -> None:
        self.repository = repository
        self.daily_limit = daily_limit
        self.quota_timezone = quota_timezone
        self.artifact_ttl = artifact_ttl
        self.allowed_test_origins = allowed_test_origins
        resolved_secrets = digest_secrets
        if active_digest_key_version not in resolved_secrets:
            raise ValueError("active cloud task digest key version is missing")
        self.digest_secrets = {
            version: secret.encode("utf-8")
            for version, secret in resolved_secrets.items()
            if version >= 1 and secret
        }
        if len(self.digest_secrets) != len(resolved_secrets):
            raise ValueError("cloud task digest keys must be non-empty")
        self.active_digest_key_version = active_digest_key_version

    def create(
        self,
        *,
        user_id: UUID,
        analysis_id: UUID,
        target_url: str,
        now: datetime | None = None,
    ) -> CloudScanTask:
        try:
            validated = validate_target_url(
                target_url,
                allowed_test_origins=self.allowed_test_origins,
            )
            if fixture_for_url(validated.url) is None:
                resolve_and_validate_target(
                    validated,
                    allowed_test_origins=self.allowed_test_origins,
                )
        except UnsafeTargetError as exc:
            raise AppError(
                code=exc.code,
                message=exc.message,
                status_code=400,
            ) from exc

        created_at = now or datetime.now(UTC)
        task = CloudScanTask(
            id=uuid4(),
            user_id=user_id,
            analysis_id=analysis_id,
            status=TaskStatus.QUEUED,
            target_url=validated.url,
            evidence=None,
            error_code=None,
            created_at=created_at,
            started_at=None,
            completed_at=None,
            expires_at=None,
            duration_ms=None,
        )
        quota_date = created_at.astimezone(self.quota_timezone).date()
        candidate_digests = {
            version: self._target_digest(validated.url, version)
            for version in self.digest_secrets
        }
        try:
            creation = self.repository.create_and_consume_quota(
                task,
                quota_date=quota_date,
                daily_limit=self.daily_limit,
                target_digest=candidate_digests[self.active_digest_key_version],
                digest_key_version=self.active_digest_key_version,
                candidate_digests=candidate_digests,
            )
        except QuotaExceededError as exc:
            raise AppError(
                code="QUOTA_EXHAUSTED",
                message="今日深度分析额度已用完",
                status_code=429,
            ) from exc
        except TaskInputConflictError as exc:
            raise AppError(
                code="CLOUD_ANALYSIS_INPUT_CONFLICT",
                message="该分析 ID 已绑定其他云扫描输入",
                status_code=409,
            ) from exc
        except TaskResultExpiredError as exc:
            raise AppError(
                code="CLOUD_TASK_RESULT_EXPIRED",
                message="该分析 ID 的云扫描结果已清除",
                status_code=409,
            ) from exc
        if creation.replayed and creation.task.status == TaskStatus.EXPIRED:
            raise AppError(
                code="CLOUD_TASK_RESULT_EXPIRED",
                message="该分析 ID 的云扫描结果已过期",
                status_code=409,
            )
        return creation.task

    def start(self, task_id: UUID, now: datetime | None = None) -> CloudScanTask:
        return self._transition(
            task_id,
            from_statuses={TaskStatus.QUEUED},
            to_status=TaskStatus.RUNNING,
            started_at=now or datetime.now(UTC),
        )

    def succeed(
        self,
        task_id: UUID,
        *,
        evidence: dict[str, object],
        duration_ms: int,
        now: datetime | None = None,
    ) -> CloudScanTask:
        completed_at = now or datetime.now(UTC)
        return self._transition(
            task_id,
            from_statuses={TaskStatus.RUNNING},
            to_status=TaskStatus.SUCCEEDED,
            completed_at=completed_at,
            expires_at=completed_at + self.artifact_ttl,
            duration_ms=duration_ms,
            evidence=evidence,
            clear_target_url=True,
        )

    def fail(
        self,
        task_id: UUID,
        *,
        error_code: str,
        evidence: dict[str, object] | None,
        duration_ms: int,
        now: datetime | None = None,
    ) -> CloudScanTask:
        completed_at = now or datetime.now(UTC)
        return self._transition(
            task_id,
            from_statuses={TaskStatus.QUEUED, TaskStatus.RUNNING},
            to_status=TaskStatus.FAILED,
            completed_at=completed_at,
            expires_at=completed_at + self.artifact_ttl,
            duration_ms=duration_ms,
            evidence=evidence,
            error_code=error_code,
            clear_target_url=True,
        )

    def get_for_owner(self, task_id: UUID, user_id: UUID) -> CloudScanTask:
        task = self.repository.get_for_owner(task_id, user_id)
        if task is None:
            raise AppError(
                code="CLOUD_TASK_NOT_FOUND",
                message="云端分析任务不存在",
                status_code=404,
            )
        return task

    def delete_for_owner(self, task_id: UUID, user_id: UUID) -> bool:
        return self.repository.delete_for_owner(task_id, user_id)

    def expire_due(self, now: datetime | None = None) -> int:
        return self.repository.expire_due(now or datetime.now(UTC))

    def _transition(self, task_id: UUID, **updates) -> CloudScanTask:
        try:
            return self.repository.transition(task_id, **updates)
        except TaskNotFoundError as exc:
            raise AppError(
                code="CLOUD_TASK_NOT_FOUND",
                message="云端分析任务不存在",
                status_code=404,
            ) from exc
        except InvalidTaskTransitionError as exc:
            raise AppError(
                code="CLOUD_TASK_INVALID_STATE",
                message="云端分析任务状态不允许该操作",
                status_code=409,
            ) from exc

    def _target_digest(self, target_url: str, key_version: int) -> str:
        secret = self.digest_secrets.get(key_version)
        if secret is None:
            raise ValueError("cloud task digest key version is unavailable")
        payload = f"taplens-cloud-scan-v1\n{target_url}".encode("utf-8")
        return hmac.new(secret, payload, hashlib.sha256).hexdigest()
