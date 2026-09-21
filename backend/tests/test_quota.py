import asyncio
from datetime import UTC, datetime
from uuid import UUID
from zoneinfo import ZoneInfo

import pytest
from httpx import ASGITransport, AsyncClient, Response

from app.core.config import Settings
from app.core.errors import AppError
from app.main import create_app
from app.quota.service import QuotaService
from app.storage.quota import QuotaRepository


TEST_SECRET = "test-secret-that-is-long-enough-for-quota-tests"


def test_quota_endpoint_requires_login(tmp_path) -> None:
    app = build_test_app(tmp_path)

    response = request(app, "GET", "/api/v1/quota")

    assert response.status_code == 401
    assert response.json()["error"]["code"] == "AUTH_TOKEN_MISSING"


def test_new_user_receives_full_daily_quota(tmp_path) -> None:
    app = build_test_app(tmp_path)
    token, _ = register_and_login(app)

    response = request(
        app,
        "GET",
        "/api/v1/quota",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    assert response.json()["daily_limit"] == 3
    assert response.json()["used"] == 0
    assert response.json()["remaining"] == 3


def test_quota_consumption_stops_at_daily_limit(tmp_path) -> None:
    app = build_test_app(tmp_path)
    _, user_id = register_and_login(app)
    service = QuotaService(
        repository=QuotaRepository(app.state.database),
        daily_limit=3,
        timezone=ZoneInfo("Asia/Shanghai"),
    )
    now = datetime(2026, 9, 21, 2, 0, tzinfo=UTC)

    assert service.consume(user_id, now).remaining == 2
    assert service.consume(user_id, now).remaining == 1
    assert service.consume(user_id, now).remaining == 0
    with pytest.raises(AppError) as captured:
        service.consume(user_id, now)

    assert captured.value.code == "QUOTA_EXHAUSTED"
    assert service.snapshot(user_id, now).used == 3


def test_quota_reset_uses_configured_timezone(tmp_path) -> None:
    app = build_test_app(tmp_path)
    _, user_id = register_and_login(app)
    service = QuotaService(
        repository=QuotaRepository(app.state.database),
        daily_limit=3,
        timezone=ZoneInfo("Asia/Shanghai"),
    )
    now = datetime(2026, 9, 21, 15, 59, tzinfo=UTC)

    snapshot = service.snapshot(user_id, now)

    assert snapshot.resets_at == datetime(2026, 9, 21, 16, 0, tzinfo=UTC)


def build_test_app(tmp_path):
    settings = Settings(
        environment="test",
        database_path=tmp_path / "taplens-quota-test.db",
        jwt_secret=TEST_SECRET,
        access_token_minutes=60,
        daily_quota_limit=3,
        quota_timezone="Asia/Shanghai",
    )
    app = create_app(settings)
    app.state.database.initialize()
    return app


def register_and_login(app) -> tuple[str, UUID]:
    credentials = {"username": "Quota_User", "password": "correct-horse"}
    registration = request(app, "POST", "/api/v1/auth/register", json=credentials)
    login = request(app, "POST", "/api/v1/auth/login", json=credentials)
    return login.json()["access_token"], UUID(registration.json()["user_id"])


def request(app, method: str, path: str, **kwargs) -> Response:
    async def send() -> Response:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await client.request(method, path, **kwargs)

    return asyncio.run(send())
