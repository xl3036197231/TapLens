from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Request
from fastapi.security import HTTPAuthorizationCredentials

from app.ai.service import AiAnalysisService
from app.ai.status_contract import project_ai_status
from app.ai.provider import AiProvider, SchoolOpenAiProvider
from app.ai.schemas import AiAnalyzeRequest, AiAnalyzeResponse
from app.auth.dependencies import bearer_scheme, current_user_id
from app.core.errors import AppError


router = APIRouter(prefix="/ai", tags=["ai"])


def provider(request: Request) -> AiProvider:
    injected = getattr(request.app.state, "ai_provider", None)
    if injected is not None:
        return injected
    settings = request.app.state.settings
    if not settings.llm_enabled:
        raise AppError(
            code="AI_PROVIDER_DISABLED",
            message="学校模型尚未启用",
            status_code=503,
        )
    return SchoolOpenAiProvider(settings)


@router.post("/analyze", response_model=AiAnalyzeResponse)
async def analyze(
    payload: AiAnalyzeRequest,
    request: Request,
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme),
    ],
) -> AiAnalyzeResponse:
    user_id = current_user_id(request, credentials)
    raw_payload = await request.json()
    if not isinstance(raw_payload, dict):
        raise AppError(
            code="AI_REQUEST_INVALID",
            message="请求字段无效",
            status_code=422,
        )
    raw_context = raw_payload.get("report_context")
    if not isinstance(raw_context, dict) or not isinstance(
        raw_context.get("created_at"), str
    ):
        raise AppError(
            code="AI_REQUEST_INVALID",
            message="report_context.created_at 必须是时区完整的文本",
            status_code=422,
        )
    service = AiAnalysisService(request.app.state.ai_call_repository, provider(request))
    return await service.analyze(
        user_id=user_id,
        payload=payload,
        payload_data=raw_payload,
    )


@router.get("/analyses/{analysis_id}/status")
def analysis_status(
    analysis_id: UUID,
    request: Request,
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme),
    ],
) -> dict[str, object]:
    user_id = current_user_id(request, credentials)
    record = request.app.state.ai_call_repository.get_for_owner(
        user_id=user_id,
        analysis_id=analysis_id,
    )
    return project_ai_status(analysis_id=analysis_id, record=record)
