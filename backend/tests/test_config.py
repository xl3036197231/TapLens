import pytest
from pydantic import ValidationError

from app.core.config import Settings


def test_development_accepts_and_normalizes_exact_loopback_origin(tmp_path) -> None:
    settings = Settings(
        environment="development",
        database_path=tmp_path / "test.db",
        test_allowed_origins="http://127.0.0.1:8765/, http://127.0.0.1:8765",
    )

    assert settings.allowed_test_origins == ("http://127.0.0.1:8765",)


@pytest.mark.parametrize(
    "origin",
    [
        "http://localhost:8765",
        "http://0.0.0.0:8765",
        "http://192.168.1.10:8765",
        "https://127.0.0.1:8765",
        "http://127.0.0.1",
        "http://127.0.0.1:8765/path",
    ],
)
def test_test_origin_rejects_non_exact_loopback_origin(tmp_path, origin: str) -> None:
    with pytest.raises(ValidationError):
        Settings(
            environment="test",
            database_path=tmp_path / "test.db",
            test_allowed_origins=origin,
        )


@pytest.mark.parametrize("environment", ["staging", "production"])
def test_public_environment_forbids_test_origin(tmp_path, environment: str) -> None:
    with pytest.raises(
        ValidationError,
        match="staging and production forbid test_allowed_origins",
    ):
        Settings(
            environment=environment,
            database_path=tmp_path / "test.db",
            public_base_url="https://api.example",
            jwt_secret="a-production-secret-that-is-at-least-32-characters",
            test_allowed_origins="http://127.0.0.1:8765",
        )


def test_staging_accepts_http_public_base_url_with_strong_secret(tmp_path) -> None:
    settings = Settings(
        environment="staging",
        database_path=tmp_path / "test.db",
        public_base_url="http://203.0.113.10",
        jwt_secret="a-staging-secret-that-is-at-least-32-characters",
    )

    assert settings.environment == "staging"
    assert settings.public_base_url == "http://203.0.113.10"
