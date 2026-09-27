from typing import Annotated

from fastapi import APIRouter, Depends, Request
from fastapi.security import HTTPAuthorizationCredentials

from app.ai.guard import validate_and_finalize_report
from app.ai.provider import AiProvider, SchoolOpenAiProvider
from app.ai.schemas import AiAnalyzeRequest, AiAnalyzeResponse, AiUsage
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
    current_user_id(request, credentials)
    result = await provider(request).analyze(payload.model_dump(mode="json"))
    report = validate_and_finalize_report(payload, result)
    return AiAnalyzeResponse(
        analysis_id=payload.report_context.analysis_id,
        report=report,
        usage=AiUsage(
            prompt_tokens=result.prompt_tokens,
            completion_tokens=result.completion_tokens,
            total_tokens=result.total_tokens,
            model=result.model,
        ),
    )
