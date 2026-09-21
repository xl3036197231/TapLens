from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID


class TaskStatus(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    EXPIRED = "expired"


TERMINAL_STATUSES = {
    TaskStatus.SUCCEEDED,
    TaskStatus.FAILED,
    TaskStatus.EXPIRED,
}


@dataclass(frozen=True)
class CloudScanTask:
    id: UUID
    user_id: UUID
    analysis_id: UUID
    status: TaskStatus
    target_url: str | None
    evidence: dict[str, object] | None
    error_code: str | None
    created_at: datetime
    started_at: datetime | None
    completed_at: datetime | None
    expires_at: datetime | None
    duration_ms: int | None
