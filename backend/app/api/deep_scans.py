from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Annotated
from uuid import UUID
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Request, Response, status
from fastapi.responses import FileResponse
from fastapi.security import HTTPAuthorizationCredentials

from app.auth.dependencies import bearer_scheme, current_user_id
from app.core.errors import AppError
from app.quota.service import QuotaService
from app.storage.quota import QuotaRepository
from app.storage.tasks import TaskRepository
from app.tasks.models import CloudScanTask, TaskStatus
from app.tasks.schemas import (
    DeepScanCreateRequest,
    DeepScanCreateResponse,
    DeepScanTaskResponse,
    TaskErrorResponse,
)
from app.tasks.service import TaskService


router = APIRouter(prefix="/deep-scans", tags=["deep scans"])
POLLING_INTERVAL_SECONDS = 2


def task_service(request: Request) -> TaskService:
    settings = request.app.state.settings
    return TaskService(
        repository=TaskRepository(request.app.state.database),
        daily_limit=settings.daily_quota_limit,
        quota_timezone=ZoneInfo(settings.quota_timezone),
        artifact_ttl=timedelta(minutes=settings.artifact_ttl_minutes),
        allowed_test_origins=settings.allowed_test_origins,
    )


def quota_service(request: Request) -> QuotaService:
    settings = request.app.state.settings
    return QuotaService(
        repository=QuotaRepository(request.app.state.database),
        daily_limit=settings.daily_quota_limit,
        timezone=ZoneInfo(settings.quota_timezone),
    )


def authenticated_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None,
) -> UUID:
    return current_user_id(request, credentials)


@router.post(
    "",
    response_model=DeepScanCreateResponse,
    status_code=status.HTTP_202_ACCEPTED,
)
def create_deep_scan(
    payload: DeepScanCreateRequest,
    request: Request,
    response: Response,
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme),
    ],
) -> DeepScanCreateResponse:
    user_id = authenticated_user(request, credentials)
    now = datetime.now(UTC)
    task = task_service(request).create(
        user_id=user_id,
        analysis_id=payload.analysis_id,
        target_url=payload.url,
        now=now,
    )
    remaining = quota_service(request).snapshot(user_id, now=now).remaining
    response.headers["Location"] = f"/api/v1/deep-scans/{task.id}"
    response.headers["Retry-After"] = str(POLLING_INTERVAL_SECONDS)
    return DeepScanCreateResponse(
        task_id=task.id,
        status=task.status,
        remaining=remaining,
    )


@router.get("/{task_id}", response_model=DeepScanTaskResponse)
def get_deep_scan(
    task_id: UUID,
    request: Request,
    response: Response,
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme),
    ],
) -> DeepScanTaskResponse:
    user_id = authenticated_user(request, credentials)
    service = task_service(request)
    service.expire_due()
    task = service.get_for_owner(task_id, user_id)
    if task.status == TaskStatus.EXPIRED:
        raise AppError(
            code="CLOUD_TASK_EXPIRED",
            message="云端分析任务已过期",
            status_code=410,
        )
    if task.status in {TaskStatus.QUEUED, TaskStatus.RUNNING}:
        response.headers["Retry-After"] = str(POLLING_INTERVAL_SECONDS)
    return response_from_task(task)


@router.get("/{task_id}/screenshot", response_class=FileResponse)
def get_deep_scan_screenshot(
    task_id: UUID,
    request: Request,
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme),
    ],
) -> FileResponse:
    user_id = authenticated_user(request, credentials)
    service = task_service(request)
    service.expire_due()
    task = service.get_for_owner(task_id, user_id)
    if task.status == TaskStatus.EXPIRED:
        raise AppError(
            code="CLOUD_ARTIFACT_EXPIRED",
            message="云端截图已过期",
            status_code=410,
        )
    if task.status in {TaskStatus.QUEUED, TaskStatus.RUNNING}:
        raise AppError(
            code="CLOUD_SCREENSHOT_NOT_READY",
            message="云端截图尚未生成",
            status_code=409,
            retryable=True,
        )
    if not has_screenshot(task):
        raise AppError(
            code="CLOUD_SCREENSHOT_NOT_FOUND",
            message="该任务没有可用截图",
            status_code=404,
        )

    artifact_path = screenshot_path(request, task.id)
    if not artifact_path.is_file():
        raise AppError(
            code="CLOUD_SCREENSHOT_NOT_FOUND",
            message="该任务没有可用截图",
            status_code=404,
        )
    return FileResponse(
        artifact_path,
        media_type="image/png",
        filename=f"taplens-{task.id}.png",
        headers={"Cache-Control": "private, no-store"},
    )


@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_deep_scan(
    task_id: UUID,
    request: Request,
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme),
    ],
) -> Response:
    user_id = authenticated_user(request, credentials)
    deleted = task_service(request).delete_for_owner(task_id, user_id)
    if deleted:
        screenshot_path(request, task_id).unlink(missing_ok=True)
    return Response(status_code=status.HTTP_204_NO_CONTENT)


def response_from_task(task: CloudScanTask) -> DeepScanTaskResponse:
    error = None
    if task.status == TaskStatus.FAILED and task.error_code:
        error = TaskErrorResponse(
            code=task.error_code,
            message="云端深度分析失败",
            retryable=task.error_code in {"CLOUD_TASK_TIMEOUT", "CLOUD_BROWSER_ERROR"},
        )
    return DeepScanTaskResponse(
        task_id=task.id,
        analysis_id=task.analysis_id,
        status=task.status,
        created_at=task.created_at,
        started_at=task.started_at,
        completed_at=task.completed_at,
        expires_at=task.expires_at,
        duration_ms=task.duration_ms,
        cloud_evidence=task.evidence,
        error=error,
    )


def has_screenshot(task: CloudScanTask) -> bool:
    if not task.evidence:
        return False
    screenshot = task.evidence.get("screenshot")
    return isinstance(screenshot, dict) and bool(screenshot.get("artifact_id"))


def screenshot_path(request: Request, task_id: UUID) -> Path:
    return request.app.state.settings.artifact_directory / f"{task_id}.png"
