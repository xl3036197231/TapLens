from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, Field

from app.tasks.models import TaskStatus


TargetUrl = Annotated[str, Field(min_length=1, max_length=2048)]


class DeepScanCreateRequest(BaseModel):
    analysis_id: UUID
    url: TargetUrl


class DeepScanCreateResponse(BaseModel):
    task_id: UUID
    status: TaskStatus
    remaining: int = Field(ge=0)


class TaskErrorResponse(BaseModel):
    code: str
    message: str
    retryable: bool
    details: dict[str, object] | None = None


class DeepScanTaskResponse(BaseModel):
    task_id: UUID
    analysis_id: UUID
    status: TaskStatus
    created_at: datetime
    started_at: datetime | None
    completed_at: datetime | None
    expires_at: datetime | None
    duration_ms: int | None = Field(default=None, ge=0)
    cloud_evidence: dict[str, object] | None
    error: TaskErrorResponse | None
