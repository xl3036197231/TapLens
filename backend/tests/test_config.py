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


def test_production_forbids_test_origin(tmp_path) -> None:
    with pytest.raises(ValidationError, match="production forbids test_allowed_origins"):
        Settings(
            environment="production",
            database_path=tmp_path / "test.db",
            public_base_url="https://api.example",
            jwt_secret="a-production-secret-that-is-at-least-32-characters",
            test_allowed_origins="http://127.0.0.1:8765",
        )
