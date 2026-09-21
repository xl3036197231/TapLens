from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI

from app.api.auth import router as auth_router
from app.api.health import router as health_router
from app.api.quota import router as quota_router
from app.core.config import Settings, get_settings
from app.core.errors import install_error_handlers
from app.storage.database import Database


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    app.state.database.initialize()
    yield


def create_app(settings: Settings | None = None) -> FastAPI:
    resolved_settings = settings or get_settings()
    application = FastAPI(
        title="TapLens Backend",
        version="0.1.0",
        description="TapLens account, quota and isolated web analysis service.",
        lifespan=lifespan,
    )
    application.state.settings = resolved_settings
    application.state.database = Database(resolved_settings.database_path)
    install_error_handlers(application)
    application.include_router(health_router, prefix="/api/v1")
    application.include_router(auth_router, prefix="/api/v1")
    application.include_router(quota_router, prefix="/api/v1")
    return application


app = create_app()
