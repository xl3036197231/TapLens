import asyncio
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import jwt
from httpx import ASGITransport, AsyncClient, Response

from app.auth.passwords import PasswordService
from app.auth.tokens import TokenService
from app.core.config import Settings
from app.main import create_app
from app.storage.users import UserRepository


TEST_SECRET = "test-secret-that-is-long-enough-for-jwt-tests"


def test_password_is_stored_as_argon2_hash(tmp_path) -> None:
    app = build_test_app(tmp_path)

    response = request(
        app,
        "POST",
        "/api/v1/auth/register",
        json={"username": "Student_01", "password": "correct-horse"},
    )

    assert response.status_code == 201
    stored = UserRepository(app.state.database).find_by_normalized_username("student_01")
    assert stored is not None
    assert stored.password_hash != "correct-horse"
    assert stored.password_hash.startswith("$argon2id$")
    assert PasswordService().verify(stored.password_hash, "correct-horse")


def test_registration_rejects_case_insensitive_duplicate(tmp_path) -> None:
    app = build_test_app(tmp_path)
    payload = {"username": "Student_01", "password": "correct-horse"}
    assert request(app, "POST", "/api/v1/auth/register", json=payload).status_code == 201

    response = request(
        app,
        "POST",
        "/api/v1/auth/register",
        json={"username": "student_01", "password": "another-password"},
    )

    assert response.status_code == 409
    assert response.json() == {
        "error": {
            "code": "AUTH_USERNAME_TAKEN",
            "message": "用户名已被使用",
            "retryable": False,
            "details": None,
        }
    }


def test_registration_rejects_unknown_fields_without_echoing_them(tmp_path) -> None:
    app = build_test_app(tmp_path)
    secret = "sk-test-must-never-be-accepted"

    response = request(
        app,
        "POST",
        "/api/v1/auth/register",
        json={
            "username": "Strict_User",
            "password": "correct-horse",
            "deepseek_key": secret,
        },
    )

    assert response.status_code == 422
    assert response.json()["error"]["code"] == "AUTH_REQUEST_INVALID"
    assert secret not in response.text
    assert UserRepository(app.state.database).find_by_normalized_username("strict_user") is None


def test_login_returns_decodable_access_token(tmp_path) -> None:
    app = build_test_app(tmp_path)
    credentials = {"username": "Student_01", "password": "correct-horse"}
    registration = request(app, "POST", "/api/v1/auth/register", json=credentials)

    response = request(app, "POST", "/api/v1/auth/login", json=credentials)

    assert response.status_code == 200
    payload = response.json()
    assert payload["token_type"] == "bearer"
    assert payload["user"]["user_id"] == registration.json()["user_id"]
    assert (
        TokenService(secret=TEST_SECRET, access_token_minutes=60).decode_access_token(
            payload["access_token"]
        )
        == UUID(registration.json()["user_id"])
    )


def test_login_does_not_reveal_whether_username_exists(tmp_path) -> None:
    app = build_test_app(tmp_path)
    request(
        app,
        "POST",
        "/api/v1/auth/register",
        json={"username": "Student_01", "password": "correct-horse"},
    )

    unknown_user = request(
        app,
        "POST",
        "/api/v1/auth/login",
        json={"username": "Unknown_01", "password": "wrong-password"},
    )
    wrong_password = request(
        app,
        "POST",
        "/api/v1/auth/login",
        json={"username": "Student_01", "password": "wrong-password"},
    )

    assert unknown_user.status_code == wrong_password.status_code == 401
    assert unknown_user.json() == wrong_password.json()


def test_expired_token_is_rejected() -> None:
    service = TokenService(secret=TEST_SECRET, access_token_minutes=5)
    token, _ = service.issue_access_token(
        user_id=uuid4(),
        now=datetime.now(UTC) - timedelta(minutes=10),
    )

    try:
        service.decode_access_token(token)
    except jwt.ExpiredSignatureError:
        pass
    else:
        raise AssertionError("expired token was accepted")


def build_test_app(tmp_path):
    settings = Settings(
        environment="test",
        database_path=tmp_path / "taplens-test.db",
        jwt_secret=TEST_SECRET,
        access_token_minutes=60,
    )
    app = create_app(settings)
    app.state.database.initialize()
    return app


def request(app, method: str, path: str, **kwargs) -> Response:
    async def send() -> Response:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await client.request(method, path, **kwargs)

    return asyncio.run(send())
