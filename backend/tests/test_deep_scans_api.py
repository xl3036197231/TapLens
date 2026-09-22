import asyncio
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID, uuid4
from zoneinfo import ZoneInfo

from httpx import ASGITransport, AsyncClient, Response

from app.core.config import Settings
from app.main import create_app
from app.sandbox.collector import CollectorResult
from app.storage.tasks import TaskRepository
from app.tasks.executor import TaskExecutor
from app.tasks.service import TaskService


TEST_SECRET = "test-secret-that-is-long-enough-for-deep-scan-tests"


class FlowCollector:
    async def collect(self, *, task_id: str, target_url: str) -> CollectorResult:
        return CollectorResult(
            final_url="https://result.example/page",
            title="Flow result",
            text_summary="Controlled end-to-end test result.",
            redirects=[],
            requests=[{
                "origin": "https://result.example",
                "method": "GET",
                "resource_type": "document",
                "status_code": 200,
            }],
            forms=[],
            blocked_actions=[],
            screenshot_path=Path(f"/tmp/{task_id}.png"),
            limitations=[],
        )


def test_register_login_create_execute_and_query_complete_flow(tmp_path) -> None:
    app = build_test_app(tmp_path)
    credentials = {"username": "Flow_User", "password": "correct-horse"}

    registration = request(app, "POST", "/api/v1/auth/register", json=credentials)
    assert registration.status_code == 201
    login = request(app, "POST", "/api/v1/auth/login", json=credentials)
    assert login.status_code == 200
    token = login.json()["access_token"]

    created = request(
        app,
        "POST",
        "/api/v1/deep-scans",
        token=token,
        json={"analysis_id": str(uuid4()), "url": "https://8.8.8.8/flow"},
    )
    assert created.status_code == 202
    assert created.json()["remaining"] == 1
    task_id = UUID(created.json()["task_id"])

    repository = TaskRepository(app.state.database)
    service = TaskService(
        repository=repository,
        daily_limit=2,
        quota_timezone=ZoneInfo("Asia/Shanghai"),
    )
    executor = TaskExecutor(
        repository=repository,
        service=service,
        collector=FlowCollector(),
        public_base_url="https://api.example",
    )
    assert asyncio.run(executor.execute(task_id)) is True

    result = request(app, "GET", f"/api/v1/deep-scans/{task_id}", token=token)
    assert result.status_code == 200
    assert result.json()["status"] == "succeeded"
    assert result.json()["cloud_evidence"]["task_id"] == str(task_id)
    assert result.json()["cloud_evidence"]["status"] == "succeeded"
    assert result.json()["error"] is None


def test_create_and_poll_deep_scan(tmp_path) -> None:
    app = build_test_app(tmp_path)
    token, _ = register_and_login(app, "Scan_User")
    analysis_id = uuid4()

    created = request(
        app,
        "POST",
        "/api/v1/deep-scans",
        token=token,
        json={"analysis_id": str(analysis_id), "url": "https://8.8.8.8/example"},
    )

    assert created.status_code == 202
    assert created.json()["status"] == "queued"
    assert created.json()["remaining"] == 1
    assert created.headers["retry-after"] == "2"
    task_id = created.json()["task_id"]
    assert created.headers["location"] == f"/api/v1/deep-scans/{task_id}"

    polled = request(app, "GET", f"/api/v1/deep-scans/{task_id}", token=token)

    assert polled.status_code == 200
    assert polled.headers["retry-after"] == "2"
    assert polled.json()["analysis_id"] == str(analysis_id)
    assert polled.json()["cloud_evidence"] is None
    assert polled.json()["error"] is None


def test_invalid_target_does_not_consume_endpoint_quota(tmp_path) -> None:
    app = build_test_app(tmp_path)
    token, _ = register_and_login(app, "Safe_User")

    rejected = request(
        app,
        "POST",
        "/api/v1/deep-scans",
        token=token,
        json={"analysis_id": str(uuid4()), "url": "http://127.0.0.1/private"},
    )
    quota = request(app, "GET", "/api/v1/quota", token=token)

    assert rejected.status_code == 400
    assert rejected.json()["error"]["code"] == "CLOUD_PRIVATE_ADDRESS_BLOCKED"
    assert quota.json()["remaining"] == 2


def test_create_rejects_deepseek_key_without_echoing_or_charging_it(tmp_path) -> None:
    app = build_test_app(tmp_path)
    token, _ = register_and_login(app, "No_Key_User")
    secret = "sk-test-must-never-reach-the-backend"

    rejected = request(
        app,
        "POST",
        "/api/v1/deep-scans",
        token=token,
        json={
            "analysis_id": str(uuid4()),
            "url": "https://8.8.8.8/example",
            "deepseek_key": secret,
        },
    )
    quota = request(app, "GET", "/api/v1/quota", token=token)

    assert rejected.status_code == 422
    assert rejected.json()["error"]["code"] == "CLOUD_REQUEST_INVALID"
    assert rejected.json()["error"]["retryable"] is False
    assert secret not in rejected.text
    assert quota.json()["remaining"] == 2


def test_screenshot_requires_owner_and_is_deleted_with_task(tmp_path) -> None:
    app = build_test_app(tmp_path)
    owner_token, owner_id = register_and_login(app, "Owner_User")
    other_token, _ = register_and_login(app, "Other_User")
    created = request(
        app,
        "POST",
        "/api/v1/deep-scans",
        token=owner_token,
        json={"analysis_id": str(uuid4()), "url": "https://8.8.8.8/example"},
    )
    task_id = UUID(created.json()["task_id"])
    service = TaskService(
        repository=TaskRepository(app.state.database),
        daily_limit=2,
        quota_timezone=ZoneInfo("Asia/Shanghai"),
    )
    service.start(task_id)
    service.succeed(
        task_id,
        evidence={
            "status": "succeeded",
            "screenshot": {"artifact_id": str(task_id)},
        },
        duration_ms=10,
    )
    screenshot = app.state.settings.artifact_directory / f"{task_id}.png"
    screenshot.parent.mkdir(parents=True, exist_ok=True)
    screenshot.write_bytes(b"\x89PNG\r\n\x1a\n")

    hidden = request(
        app,
        "GET",
        f"/api/v1/deep-scans/{task_id}/screenshot",
        token=other_token,
    )
    concealed_delete = request(
        app,
        "DELETE",
        f"/api/v1/deep-scans/{task_id}",
        token=other_token,
    )
    downloaded = request(
        app,
        "GET",
        f"/api/v1/deep-scans/{task_id}/screenshot",
        token=owner_token,
    )

    assert hidden.status_code == 404
    assert concealed_delete.status_code == 204
    assert screenshot.exists()
    assert downloaded.status_code == 200
    assert downloaded.headers["content-type"] == "image/png"
    assert downloaded.headers["cache-control"] == "private, no-store"

    deleted = request(
        app,
        "DELETE",
        f"/api/v1/deep-scans/{task_id}",
        token=owner_token,
    )
    assert deleted.status_code == 204
    assert not screenshot.exists()
    assert TaskRepository(app.state.database).get(task_id) is None
    assert owner_id != UUID(int=0)


def test_failed_task_returns_stable_error(tmp_path) -> None:
    app = build_test_app(tmp_path)
    token, _ = register_and_login(app, "Failure_User")
    created = request(
        app,
        "POST",
        "/api/v1/deep-scans",
        token=token,
        json={"analysis_id": str(uuid4()), "url": "https://8.8.8.8/example"},
    )
    task_id = UUID(created.json()["task_id"])
    service = TaskService(
        repository=TaskRepository(app.state.database),
        daily_limit=2,
        quota_timezone=ZoneInfo("Asia/Shanghai"),
    )
    service.start(task_id)
    service.fail(
        task_id,
        error_code="CLOUD_TASK_TIMEOUT",
        evidence={"status": "failed", "error": {"code": "CLOUD_TASK_TIMEOUT"}},
        duration_ms=15000,
    )

    response = request(app, "GET", f"/api/v1/deep-scans/{task_id}", token=token)

    assert response.status_code == 200
    assert "retry-after" not in response.headers
    assert response.json()["status"] == "failed"
    assert response.json()["error"] == {
        "code": "CLOUD_TASK_TIMEOUT",
        "message": "云端深度分析失败",
        "retryable": True,
        "details": None,
    }


def build_test_app(tmp_path):
    settings = Settings(
        environment="test",
        database_path=tmp_path / "taplens-deep-scans-test.db",
        artifact_directory=tmp_path / "artifacts",
        jwt_secret=TEST_SECRET,
        access_token_minutes=60,
        daily_quota_limit=2,
        quota_timezone="Asia/Shanghai",
    )
    app = create_app(settings)
    app.state.database.initialize()
    return app


def register_and_login(app, username: str) -> tuple[str, UUID]:
    credentials = {"username": username, "password": "correct-horse"}
    registration = request(app, "POST", "/api/v1/auth/register", json=credentials)
    login = request(app, "POST", "/api/v1/auth/login", json=credentials)
    return login.json()["access_token"], UUID(registration.json()["user_id"])


def request(
    app,
    method: str,
    path: str,
    *,
    token: str | None = None,
    **kwargs,
) -> Response:
    async def send() -> Response:
        transport = ASGITransport(app=app)
        headers = kwargs.pop("headers", {})
        if token:
            headers["Authorization"] = f"Bearer {token}"
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await client.request(method, path, headers=headers, **kwargs)

    return asyncio.run(send())
