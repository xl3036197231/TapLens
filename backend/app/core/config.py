from functools import lru_cache
from pathlib import Path
from typing import Literal
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


BACKEND_ROOT = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="TAPLENS_",
        extra="ignore",
    )

    environment: Literal["development", "test", "production"] = "development"
    host: str = "127.0.0.1"
    port: int = Field(default=8000, ge=1, le=65535)
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"
    database_path: Path = Field(default_factory=lambda: BACKEND_ROOT / "data/taplens.db")
    jwt_secret: SecretStr = SecretStr("development-only-change-me")
    access_token_minutes: int = Field(default=60, ge=5, le=1440)
    daily_quota_limit: int = Field(default=10, ge=1, le=1000)
    quota_timezone: str = "Asia/Shanghai"

    @model_validator(mode="after")
    def require_production_jwt_secret(self) -> "Settings":
        secret = self.jwt_secret.get_secret_value()
        if self.environment == "production" and (
            secret in {"development-only-change-me", "replace-me-before-auth-is-enabled"}
            or len(secret) < 32
        ):
            raise ValueError("production requires a random JWT secret of at least 32 characters")
        try:
            ZoneInfo(self.quota_timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("quota_timezone must be a valid IANA timezone") from exc
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
