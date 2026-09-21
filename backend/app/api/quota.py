from typing import Annotated
from uuid import UUID
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Request
from fastapi.security import HTTPAuthorizationCredentials

from app.auth.dependencies import bearer_scheme, current_user_id
from app.quota.schemas import QuotaResponse
from app.quota.service import QuotaService
from app.storage.quota import QuotaRepository


router = APIRouter(tags=["quota"])


@router.get("/quota", response_model=QuotaResponse)
def quota(
    request: Request,
    credentials: Annotated[
        HTTPAuthorizationCredentials | None,
        Depends(bearer_scheme),
    ],
) -> QuotaResponse:
    user_id: UUID = current_user_id(request, credentials)
    settings = request.app.state.settings
    service = QuotaService(
        repository=QuotaRepository(request.app.state.database),
        daily_limit=settings.daily_quota_limit,
        timezone=ZoneInfo(settings.quota_timezone),
    )
    return service.snapshot(user_id)
