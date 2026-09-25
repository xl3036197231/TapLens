from functools import lru_cache
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit
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

    environment: Literal["development", "test", "staging", "production"] = "development"
    host: str = "127.0.0.1"
    port: int = Field(default=8000, ge=1, le=65535)
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"
    database_path: Path = Field(default_factory=lambda: BACKEND_ROOT / "data/taplens.db")
    artifact_directory: Path = Field(default_factory=lambda: BACKEND_ROOT / "data/artifacts")
    artifact_ttl_minutes: int = Field(default=30, ge=1, le=1440)
    public_base_url: str = "http://127.0.0.1:8000"
    jwt_secret: SecretStr = SecretStr("development-only-change-me")
    access_token_minutes: int = Field(default=60, ge=5, le=1440)
    daily_quota_limit: int = Field(default=10, ge=1, le=1000)
    quota_timezone: str = "Asia/Shanghai"
    test_allowed_origins: str = ""

    @model_validator(mode="after")
    def require_production_jwt_secret(self) -> "Settings":
        secret = self.jwt_secret.get_secret_value()
        if self.environment in {"staging", "production"} and (
            secret in {"development-only-change-me", "replace-me-before-auth-is-enabled"}
            or len(secret) < 32
        ):
            raise ValueError(
                "staging and production require a random JWT secret of at least 32 characters"
            )
        try:
            ZoneInfo(self.quota_timezone)
        except ZoneInfoNotFoundError as exc:
            raise ValueError("quota_timezone must be a valid IANA timezone") from exc
        public_url = urlsplit(self.public_base_url)
        if (
            public_url.scheme not in {"http", "https"}
            or not public_url.netloc
            or public_url.path not in {"", "/"}
            or public_url.query
            or public_url.fragment
        ):
            raise ValueError("public_base_url must be an HTTP(S) origin without path or query")
        if self.environment == "production" and public_url.scheme != "https":
            raise ValueError("production requires an HTTPS public_base_url")
        normalized_test_origins = tuple(
            normalize_test_origin(origin.strip())
            for origin in self.test_allowed_origins.split(",")
            if origin.strip()
        )
        if self.environment in {"staging", "production"} and normalized_test_origins:
            raise ValueError("staging and production forbid test_allowed_origins")
        self.public_base_url = self.public_base_url.rstrip("/")
        self.test_allowed_origins = ",".join(dict.fromkeys(normalized_test_origins))
        return self

    @property
    def allowed_test_origins(self) -> tuple[str, ...]:
        return tuple(origin for origin in self.test_allowed_origins.split(",") if origin)


@lru_cache
def get_settings() -> Settings:
    return Settings()


def normalize_test_origin(origin: str) -> str:
    parsed = urlsplit(origin)
    try:
        port = parsed.port
    except ValueError as exc:
        raise ValueError("test_allowed_origins contains an invalid port") from exc
    if (
        parsed.scheme != "http"
        or parsed.hostname != "127.0.0.1"
        or port is None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.path not in {"", "/"}
        or parsed.query
        or parsed.fragment
    ):
        raise ValueError(
            "test_allowed_origins must contain exact http://127.0.0.1:<port> origins"
        )
    return f"http://127.0.0.1:{port}"
