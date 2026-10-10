import asyncio
from contextlib import asynccontextmanager
from collections.abc import AsyncIterator

from fastapi import FastAPI

from app.api.auth import router as auth_router
from app.api.health import router as health_router
from app.api.quota import router as quota_router
from app.api.deep_scans import router as deep_scans_router
from app.api.ai import router as ai_router
from app.api.qr_analyses import router as qr_analyses_router
from app.core.config import Settings, get_settings
from app.core.errors import install_error_handlers
from app.storage.database import Database
from app.storage.ai_calls import AiCallCleanupWorker, AiCallRepository
from app.storage.qr_analyses import QrAnalysisRepository
from app.qr_analysis.catalog import QrFixtureCatalog


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    app.state.database.initialize()
    stop = asyncio.Event()
    worker = AiCallCleanupWorker(
        app.state.ai_call_repository,
        interval_seconds=app.state.settings.ai_cleanup_interval_seconds,
    )
    task = asyncio.create_task(worker.run(stop), name="ai-call-cache-cleanup")
    try:
        yield
    finally:
        stop.set()
        await task


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
    application.state.ai_call_repository = AiCallRepository(
        application.state.database,
        digest_secrets=resolved_settings.ai_digest_secret_map,
        active_digest_key_version=resolved_settings.ai_digest_active_key_version,
        lease_seconds=resolved_settings.ai_call_lease_seconds,
        cache_hours=resolved_settings.ai_response_cache_hours,
        compact_days=resolved_settings.ai_compact_days,
    )
    application.state.qr_analysis_repository = QrAnalysisRepository(
        application.state.database,
        digest_secrets=resolved_settings.ai_digest_secret_map,
        active_digest_key_version=resolved_settings.ai_digest_active_key_version,
        cache_hours=resolved_settings.ai_response_cache_hours,
        compact_days=resolved_settings.ai_compact_days,
    )
    application.state.qr_fixture_catalog = QrFixtureCatalog()
    install_error_handlers(application)
    application.include_router(health_router, prefix="/api/v1")
    application.include_router(auth_router, prefix="/api/v1")
    application.include_router(quota_router, prefix="/api/v1")
    application.include_router(deep_scans_router, prefix="/api/v1")
    application.include_router(ai_router, prefix="/api/v1")
    application.include_router(qr_analyses_router, prefix="/api/v1")
    return application


app = create_app()
