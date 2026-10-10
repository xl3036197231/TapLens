from typing import Annotated
from uuid import UUID
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Request, Response, status
from fastapi.security import HTTPAuthorizationCredentials

from app.auth.dependencies import bearer_scheme, current_user_id
from app.core.errors import AppError
from app.qr_analysis.catalog import QrFixtureCatalog
from app.qr_analysis.schemas import QrAnalysisCreateRequest, QrAnalysisCreateResponse
from app.qr_analysis.service import QrAnalysisService, project_status


router = APIRouter(prefix="/qr-analyses", tags=["qr analyses"])
POLL_SECONDS = 2


def service(request: Request) -> QrAnalysisService:
    settings = request.app.state.settings
    return QrAnalysisService(
        request.app.state.qr_analysis_repository,
        catalog=request.app.state.qr_fixture_catalog,
        daily_limit=settings.daily_quota_limit,
        quota_timezone=ZoneInfo(settings.quota_timezone),
    )


@router.post("", response_model=QrAnalysisCreateResponse, status_code=status.HTTP_202_ACCEPTED)
async def create_qr_analysis(
    payload: QrAnalysisCreateRequest,
    request: Request,
    response: Response,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> QrAnalysisCreateResponse:
    user_id = current_user_id(request, credentials)
    if (
        payload.ai_mode == "school"
        and not request.app.state.settings.llm_enabled
        and not request.app.state.settings.qr_fake_provider_enabled
        and getattr(request.app.state, "ai_provider", None) is None
    ):
        raise AppError(code="AI_PROVIDER_DISABLED", message="学校模型尚未启用", status_code=503)
    raw = await request.json()
    if not isinstance(raw, dict) or not isinstance(raw.get("created_at"), str):
        raise AppError(code="CLOUD_REQUEST_INVALID", message="created_at 必须是时区完整的文本", status_code=422)
    reservation = service(request).create(
        user_id=user_id,
        payload=payload,
        payload_data=raw,
        created_at_text=raw["created_at"],
    )
    status_path = f"/api/v1/qr-analyses/{payload.analysis_id}/status"
    record = reservation.record
    if reservation.replayed and record.state.value in {"queued", "in_progress"}:
        raise AppError(
            code="CLOUD_TASK_INVALID_STATE",
            message="二维码分析仍在进行，请查询状态",
            status_code=409,
            details={"status_path": status_path, "poll_after_seconds": POLL_SECONDS},
        )
    if reservation.replayed and record.state.value == "outcome_unknown":
        raise AppError(
            code="AI_OUTCOME_UNKNOWN",
            message="模型请求结果待核实",
            status_code=409,
            details={"status_path": status_path, "poll_after_seconds": 5},
        )
    response.headers["Location"] = status_path
    response.headers["Retry-After"] = str(POLL_SECONDS)
    return QrAnalysisCreateResponse(
        analysis_id=record.analysis_id,
        task_id=record.task_id,
        state=record.state.value,
        phase=record.phase.value,
        status_path=status_path,
        poll_after_seconds=POLL_SECONDS,
    )


@router.get("/{analysis_id}/status")
def get_qr_analysis_status(
    analysis_id: UUID,
    request: Request,
    response: Response,
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> dict[str, object]:
    user_id = current_user_id(request, credentials)
    record = service(request).get(user_id, analysis_id)
    body = project_status(record)
    poll = body["poll_after_seconds"]
    if isinstance(poll, int):
        response.headers["Retry-After"] = str(poll)
    return body
