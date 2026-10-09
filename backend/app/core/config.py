import json
from functools import lru_cache
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from pydantic import Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


BACKEND_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_AI_DIGEST_KEYS = '{"1":"development-only-ai-digest-secret-change-me"}'


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
    llm_enabled: bool = False
    qr_fake_provider_enabled: bool = False
    llm_base_url: str = ""
    llm_api_key: SecretStr = SecretStr("")
    llm_model: str = ""
    llm_protocol: Literal["openai_chat_completions"] = "openai_chat_completions"
    llm_timeout_seconds: float = Field(default=120.0, ge=1.0, le=120.0)
    llm_proxy_url: str = ""
    ai_digest_active_key_version: int = Field(default=1, ge=1)
    ai_digest_keys: SecretStr = SecretStr(DEFAULT_AI_DIGEST_KEYS)
    ai_call_lease_seconds: int = Field(default=90, ge=10, le=600)
    ai_response_cache_hours: int = Field(default=24, ge=1, le=168)
    ai_compact_days: int = Field(default=30, ge=1, le=3650)
    ai_cleanup_interval_seconds: int = Field(default=3600, ge=10, le=86400)

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
        digest_keys = self.ai_digest_secret_map
        if self.ai_digest_active_key_version not in digest_keys:
            raise ValueError("active AI digest key version is missing")
        if self.environment in {"staging", "production"} and (
            self.ai_digest_keys.get_secret_value() == DEFAULT_AI_DIGEST_KEYS
            or any(len(secret) < 32 for secret in digest_keys.values())
        ):
            raise ValueError(
                "staging and production require independent AI digest secrets of at least 32 characters"
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
        if self.environment in {"staging", "production"} and self.qr_fake_provider_enabled:
            raise ValueError("staging and production forbid qr_fake_provider_enabled")
        if self.llm_enabled and self.qr_fake_provider_enabled:
            raise ValueError("llm_enabled and qr_fake_provider_enabled are mutually exclusive")
        self.public_base_url = self.public_base_url.rstrip("/")
        self.test_allowed_origins = ",".join(dict.fromkeys(normalized_test_origins))
        if self.llm_enabled:
            llm_url = urlsplit(self.llm_base_url)
            if (
                llm_url.scheme != "https"
                or not llm_url.netloc
                or llm_url.query
                or llm_url.fragment
                or not self.llm_api_key.get_secret_value()
                or not self.llm_model.strip()
            ):
                raise ValueError("enabled LLM requires HTTPS base URL, API key and model")
            self.llm_base_url = self.llm_base_url.rstrip("/")
            self.llm_model = self.llm_model.strip()
        if self.llm_proxy_url:
            proxy_url = urlsplit(self.llm_proxy_url)
            if (
                proxy_url.scheme not in {"http", "https"}
                or not proxy_url.netloc
                or proxy_url.path not in {"", "/"}
                or proxy_url.query
                or proxy_url.fragment
                or proxy_url.username is not None
                or proxy_url.password is not None
            ):
                raise ValueError("llm_proxy_url must be an HTTP(S) origin without credentials")
            self.llm_proxy_url = self.llm_proxy_url.rstrip("/")
        return self

    @property
    def allowed_test_origins(self) -> tuple[str, ...]:
        return tuple(origin for origin in self.test_allowed_origins.split(",") if origin)

    @property
    def ai_digest_secret_map(self) -> dict[int, str]:
        try:
            raw = json.loads(self.ai_digest_keys.get_secret_value())
            if not isinstance(raw, dict) or not raw:
                raise ValueError
            parsed = {int(version): secret for version, secret in raw.items()}
        except (TypeError, ValueError, json.JSONDecodeError) as exc:
            raise ValueError("ai_digest_keys must be a non-empty JSON object") from exc
        if any(
            version < 1 or not isinstance(secret, str) or not secret
            for version, secret in parsed.items()
        ):
            raise ValueError("AI digest key versions and secrets must be non-empty")
        return parsed


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
