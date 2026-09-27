import asyncio

from httpx import ASGITransport, AsyncClient

from app.core.config import Settings
from app.main import app, create_app


def test_health_endpoint() -> None:
    async def request_health() -> tuple[int, dict[str, str]]:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            response = await client.get("/api/v1/health")
        return response.status_code, response.json()

    status_code, payload = asyncio.run(request_health())

    assert status_code == 200
    assert payload == {
        "status": "ok",
        "service": "taplens-backend",
        "version": "0.1.0",
    }


def test_readiness_checks_database_and_artifact_storage(tmp_path) -> None:
    readiness_app = create_app(
        Settings(
            database_path=tmp_path / "data" / "taplens.db",
            artifact_directory=tmp_path / "artifacts",
        )
    )
    readiness_app.state.database.initialize()

    async def request_readiness() -> tuple[int, dict[str, object]]:
        transport = ASGITransport(app=readiness_app)
        async with AsyncClient(
            transport=transport,
            base_url="http://testserver",
        ) as client:
            response = await client.get("/api/v1/ready")
        return response.status_code, response.json()

    status_code, payload = asyncio.run(request_readiness())

    assert status_code == 200
    assert payload == {
        "status": "ready",
        "service": "taplens-backend",
        "checks": {"database": "ok", "artifacts": "ok"},
    }
