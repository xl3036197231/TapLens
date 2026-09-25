from typing import Literal

from pathlib import Path

from fastapi import APIRouter, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel


class HealthResponse(BaseModel):
    status: Literal["ok"] = "ok"
    service: Literal["taplens-backend"] = "taplens-backend"
    version: str = "0.1.0"


class ReadinessResponse(BaseModel):
    status: Literal["ready", "not_ready"]
    service: Literal["taplens-backend"] = "taplens-backend"
    checks: dict[str, Literal["ok", "failed"]]


router = APIRouter(tags=["system"])


@router.get("/health", response_model=HealthResponse)
async def health() -> HealthResponse:
    return HealthResponse()


@router.get("/ready", response_model=ReadinessResponse)
def readiness(request: Request) -> ReadinessResponse | JSONResponse:
    checks: dict[str, Literal["ok", "failed"]] = {
        "database": "failed",
        "artifacts": "failed",
    }
    try:
        with request.app.state.database.connect() as connection:
            connection.execute("SELECT 1").fetchone()
        checks["database"] = "ok"
    except Exception:
        pass

    artifact_directory: Path = request.app.state.settings.artifact_directory
    try:
        artifact_directory.mkdir(parents=True, exist_ok=True)
        probe = artifact_directory / ".readiness"
        probe.touch(exist_ok=True)
        probe.unlink(missing_ok=True)
        checks["artifacts"] = "ok"
    except OSError:
        pass

    ready = all(result == "ok" for result in checks.values())
    payload = ReadinessResponse(
        status="ready" if ready else "not_ready",
        checks=checks,
    )
    if ready:
        return payload
    return JSONResponse(
        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
        content=payload.model_dump(),
    )
