from datetime import UTC, datetime, time, timedelta
from uuid import UUID
from zoneinfo import ZoneInfo

from app.core.errors import AppError
from app.quota.schemas import QuotaResponse
from app.storage.quota import QuotaRepository


class QuotaService:
    def __init__(
        self,
        *,
        repository: QuotaRepository,
        daily_limit: int,
        timezone: ZoneInfo,
    ) -> None:
        self.repository = repository
        self.daily_limit = daily_limit
        self.timezone = timezone

    def snapshot(self, user_id: UUID, now: datetime | None = None) -> QuotaResponse:
        local_now = (now or datetime.now(UTC)).astimezone(self.timezone)
        used = self.repository.used(user_id, local_now.date())
        next_local_midnight = datetime.combine(
            local_now.date() + timedelta(days=1),
            time.min,
            tzinfo=self.timezone,
        )
        return QuotaResponse(
            daily_limit=self.daily_limit,
            used=used,
            remaining=max(0, self.daily_limit - used),
            resets_at=next_local_midnight.astimezone(UTC),
        )

    def consume(self, user_id: UUID, now: datetime | None = None) -> QuotaResponse:
        local_now = (now or datetime.now(UTC)).astimezone(self.timezone)
        if not self.repository.try_consume(user_id, local_now.date(), self.daily_limit):
            raise AppError(
                code="QUOTA_EXHAUSTED",
                message="今日深度分析额度已用完",
                status_code=429,
            )
        return self.snapshot(user_id, now=local_now)
