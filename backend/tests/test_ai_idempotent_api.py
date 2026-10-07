import asyncio
import json
from copy import deepcopy
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

from httpx import ASGITransport, AsyncClient

from app.ai.provider import ProviderResult
from app.core.config import Settings
from app.core.errors import AppError
from app.main import create_app


ROOT = Path(__file__).resolve().parents[2]
REQUEST = ROOT / "shared/fixtures/ai/day5-school-model-request.json"
REPORT = ROOT / "shared/fixtures/ai/day5-school-model-mock-report.json"
TEST_SECRET = "test-secret-that-is-long-enough-for-idempotent-ai-api"


class CountingProvider:
    def __init__(self, *, blocked: bool = False, failure: AppError | None = None) -> None:
        self.calls: list[dict[str, object]] = []
        self.failure = failure
        self.started = asyncio.Event()
        self.release = asyncio.Event()
        if not blocked:
            self.release.set()

    async def analyze(self, payload: dict[str, object]) -> ProviderResult:
        self.calls.append(deepcopy(payload))
        self.started.set()
        await self.release.wait()
        if self.failure is not None:
            raise self.failure
        report = json.loads(REPORT.read_text(encoding="utf-8"))
        report["analysis_id"] = payload["report_context"]["analysis_id"]
        report["created_at"] = payload["report_context"]["created_at"]
        return ProviderResult(
            report=report,
            prompt_tokens=120,
            completion_tokens=80,
            total_tokens=200,
            model="cuc/deepseek",
        )


class GuardRejectingProvider(CountingProvider):
    async def analyze(self, payload: dict[str, object]) -> ProviderResult:
        result = await super().analyze(payload)
        result.report["risk_level"] = "medium"
        return result


def test_success_is_cached_and_status_get_is_read_only(tmp_path) -> None:
    async def run() -> None:
        provider = CountingProvider()
        app = build_app(tmp_path, provider)
        async with client_for(app) as client:
            token = await register_and_login(client, "Cached_User")
            first = await post(client, token, body())
            replay = await post(client, token, body())

            before = app.state.database.path.read_bytes()
            status = await get_status(client, token, analysis_id())
            after = app.state.database.path.read_bytes()

        assert first.status_code == replay.status_code == 200
        assert first.json() == replay.json()
        assert status.status_code == 200
        assert status.json()["status"] == "succeeded"
        assert status.json()["result"]["usage"]["total_tokens"] == 200
        assert len(provider.calls) == 1
        assert before == after

    asyncio.run(run())


def test_twenty_concurrent_posts_dispatch_provider_once(tmp_path) -> None:
    async def run() -> None:
        provider = CountingProvider(blocked=True)
        app = build_app(tmp_path, provider)
        async with client_for(app) as client:
            token = await register_and_login(client, "Concurrent_User")
            tasks = [asyncio.create_task(post(client, token, body())) for _ in range(20)]
            await provider.started.wait()
            await asyncio.sleep(0)
            provider.release.set()
            responses = await asyncio.gather(*tasks)

        assert len(provider.calls) == 1
        assert sum(response.status_code == 200 for response in responses) == 1
        conflicts = [response for response in responses if response.status_code == 409]
        assert len(conflicts) == 19
        assert {response.json()["error"]["code"] for response in conflicts} == {
            "AI_REQUEST_IN_PROGRESS"
        }
        assert all(response.json()["error"]["retryable"] is False for response in conflicts)

    asyncio.run(run())


def test_long_provider_call_renews_the_same_attempt_lease(tmp_path) -> None:
    async def run() -> None:
        provider = CountingProvider(blocked=True)
        app = build_app(tmp_path, provider)
        app.state.ai_call_repository.lease = timedelta(milliseconds=150)
        async with client_for(app) as client:
            token = await register_and_login(client, "Lease_User")
            task = asyncio.create_task(post(client, token, body()))
            await provider.started.wait()
            with app.state.database.connect() as connection:
                initial = connection.execute(
                    "SELECT attempt_id, lease_expires_at FROM ai_analysis_calls"
                ).fetchone()
            await asyncio.sleep(0.08)
            with app.state.database.connect() as connection:
                renewed = connection.execute(
                    "SELECT attempt_id, lease_expires_at FROM ai_analysis_calls"
                ).fetchone()
            provider.release.set()
            response = await task

        assert response.status_code == 200
        assert initial["attempt_id"] == renewed["attempt_id"]
        assert renewed["lease_expires_at"] > initial["lease_expires_at"]
        assert len(provider.calls) == 1

    asyncio.run(run())


def test_equivalent_created_at_text_is_an_input_conflict_without_dispatch(tmp_path) -> None:
    async def run() -> None:
        provider = CountingProvider()
        app = build_app(tmp_path, provider)
        async with client_for(app) as client:
            token = await register_and_login(client, "Time_User")
            assert (await post(client, token, body())).status_code == 200
            changed = body()
            changed["report_context"]["created_at"] = changed["report_context"][
                "created_at"
            ].replace("Z", "+00:00")
            conflict = await post(client, token, changed)

        assert conflict.status_code == 409
        assert conflict.json()["error"]["code"] == "AI_ANALYSIS_INPUT_CONFLICT"
        assert len(provider.calls) == 1

    asyncio.run(run())


def test_definitive_provider_failure_is_terminal_and_not_retryable(tmp_path) -> None:
    async def run() -> None:
        provider = CountingProvider(
            failure=AppError(
                code="AI_PROVIDER_AUTH_FAILED",
                message="fake auth failure",
                status_code=503,
            )
        )
        app = build_app(tmp_path, provider)
        async with client_for(app) as client:
            token = await register_and_login(client, "Failure_User")
            first = await post(client, token, body())
            replay = await post(client, token, body())
            status = await get_status(client, token, analysis_id())

        assert first.status_code == 503
        assert first.json()["error"]["code"] == "AI_PROVIDER_AUTH_FAILED"
        assert first.json()["error"]["retryable"] is False
        assert replay.status_code == 409
        assert replay.json()["error"]["code"] == "AI_ANALYSIS_FAILED"
        assert status.json()["failure"]["code"] == "AI_PROVIDER_AUTH_FAILED"
        assert status.json()["usage_status"] == "unknown"
        assert len(provider.calls) == 1

    asyncio.run(run())


def test_provider_timeout_becomes_unknown_and_never_redispatches(tmp_path) -> None:
    async def run() -> None:
        provider = CountingProvider(
            failure=AppError(
                code="AI_PROVIDER_TIMEOUT",
                message="fake timeout",
                status_code=504,
                retryable=True,
            )
        )
        app = build_app(tmp_path, provider)
        async with client_for(app) as client:
            token = await register_and_login(client, "Timeout_User")
            first = await post(client, token, body())
            replay = await post(client, token, body())
            status = await get_status(client, token, analysis_id())

        assert first.status_code == replay.status_code == 409
        assert first.json()["error"]["code"] == "AI_OUTCOME_UNKNOWN"
        assert replay.json()["error"]["code"] == "AI_OUTCOME_UNKNOWN"
        assert status.json() == {
            "analysis_id": analysis_id(),
            "status": "outcome_unknown",
            "usage_status": "unknown",
        }
        assert len(provider.calls) == 1

    asyncio.run(run())


def test_guard_rejection_records_known_usage_and_never_redispatches(tmp_path) -> None:
    async def run() -> None:
        provider = GuardRejectingProvider()
        app = build_app(tmp_path, provider)
        async with client_for(app) as client:
            token = await register_and_login(client, "Guard_User")
            first = await post(client, token, body())
            replay = await post(client, token, body())
            status = await get_status(client, token, analysis_id())

        assert first.status_code == 502
        assert first.json()["error"]["code"] == "AI_REPORT_REJECTED"
        assert replay.status_code == 409
        assert replay.json()["error"]["code"] == "AI_ANALYSIS_FAILED"
        assert status.json()["status"] == "failed"
        assert status.json()["usage_status"] == "known"
        assert status.json()["usage"]["total_tokens"] == 200
        assert len(provider.calls) == 1

    asyncio.run(run())


def test_status_is_owner_isolated_and_never_obtains_provider(tmp_path) -> None:
    async def run() -> None:
        provider = CountingProvider()
        app = build_app(tmp_path, provider)
        async with client_for(app) as client:
            owner = await register_and_login(client, "Owner_User")
            other = await register_and_login(client, "Other_User")
            assert (await post(client, owner, body())).status_code == 200
            hidden = await get_status(client, other, analysis_id())
            missing = await get_status(client, other, str(uuid4()))

        assert hidden.json()["status"] == "not_found"
        assert missing.json()["status"] == "not_found"
        assert len(provider.calls) == 1

    asyncio.run(run())


def test_expired_cache_returns_result_expired_without_provider_call(tmp_path) -> None:
    async def run() -> None:
        provider = CountingProvider()
        app = build_app(tmp_path, provider)
        async with client_for(app) as client:
            token = await register_and_login(client, "Expired_User")
            assert (await post(client, token, body())).status_code == 200
            app.state.ai_call_repository.purge_expired(
                now=datetime.now(UTC) + timedelta(hours=25)
            )
            replay = await post(client, token, body())
            status = await get_status(client, token, analysis_id())

        assert replay.status_code == 409
        assert replay.json()["error"]["code"] == "AI_RESULT_EXPIRED"
        assert status.json()["status"] == "result_expired"
        assert len(provider.calls) == 1

    asyncio.run(run())


def test_lifespan_cleanup_clears_expired_response_cache(tmp_path) -> None:
    async def run() -> None:
        provider = CountingProvider()
        app = build_app(tmp_path, provider)
        async with client_for(app) as client:
            token = await register_and_login(client, "Cleanup_User")
            assert (await post(client, token, body())).status_code == 200
        with app.state.database.connect() as connection:
            connection.execute(
                "UPDATE ai_analysis_calls SET cache_expires_at = ?",
                ((datetime.now(UTC) - timedelta(seconds=1)).isoformat(),),
            )

        async with app.router.lifespan_context(app):
            await asyncio.sleep(0)

        with app.state.database.connect() as connection:
            row = connection.execute(
                "SELECT response_json, cache_expires_at FROM ai_analysis_calls"
            ).fetchone()
        assert row["response_json"] is None
        assert row["cache_expires_at"] is None

    asyncio.run(run())


def build_app(tmp_path, provider):
    app = create_app(
        Settings(
            environment="test",
            database_path=tmp_path / "taplens-test.db",
            artifact_directory=tmp_path / "artifacts",
            jwt_secret=TEST_SECRET,
            ai_cleanup_interval_seconds=10,
        )
    )
    app.state.database.initialize()
    app.state.ai_provider = provider
    return app


def client_for(app) -> AsyncClient:
    return AsyncClient(transport=ASGITransport(app=app), base_url="http://testserver")


async def register_and_login(client: AsyncClient, username: str) -> str:
    credentials = {"username": username, "password": "correct-horse"}
    assert (await client.post("/api/v1/auth/register", json=credentials)).status_code == 201
    response = await client.post("/api/v1/auth/login", json=credentials)
    assert response.status_code == 200
    return response.json()["access_token"]


async def post(client: AsyncClient, token: str, payload: dict):
    return await client.post(
        "/api/v1/ai/analyze",
        headers={"Authorization": f"Bearer {token}"},
        json=payload,
    )


async def get_status(client: AsyncClient, token: str, identifier: str):
    return await client.get(
        f"/api/v1/ai/analyses/{identifier}/status",
        headers={"Authorization": f"Bearer {token}"},
    )


def body() -> dict:
    return json.loads(REQUEST.read_text(encoding="utf-8"))


def analysis_id() -> str:
    return body()["report_context"]["analysis_id"]
