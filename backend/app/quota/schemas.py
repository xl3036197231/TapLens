from datetime import datetime

from pydantic import BaseModel, Field


class QuotaResponse(BaseModel):
    daily_limit: int = Field(ge=1)
    used: int = Field(ge=0)
    remaining: int = Field(ge=0)
    resets_at: datetime
