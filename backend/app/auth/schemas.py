from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


Username = Annotated[
    str,
    Field(min_length=3, max_length=32, pattern=r"^[A-Za-z0-9_]+$"),
]
Password = Annotated[str, Field(min_length=8, max_length=128)]


class CredentialsRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    username: Username
    password: Password


class UserResponse(BaseModel):
    user_id: UUID
    username: str
    created_at: datetime


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_at: datetime
    user: UserResponse
