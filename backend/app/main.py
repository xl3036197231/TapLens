from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI

from app.api.health import router as health_router
from app.core.config import get_settings


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    get_settings()
    yield


app = FastAPI(
    title="TapLens Backend",
    version="0.1.0",
    description="TapLens account, quota and isolated web analysis service.",
    lifespan=lifespan,
)
app.include_router(health_router, prefix="/api/v1")
