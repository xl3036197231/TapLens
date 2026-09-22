from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse


class AppError(Exception):
    def __init__(
        self,
        *,
        code: str,
        message: str,
        status_code: int,
        retryable: bool = False,
        details: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status_code = status_code
        self.retryable = retryable
        self.details = details


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(AppError)
    async def handle_app_error(_: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(
            status_code=exc.status_code,
            content={
                "error": {
                    "code": exc.code,
                    "message": exc.message,
                    "retryable": exc.retryable,
                    "details": exc.details,
                }
            },
        )

    @app.exception_handler(RequestValidationError)
    async def handle_request_validation_error(
        request: Request,
        exc: RequestValidationError,
    ) -> JSONResponse:
        """Return stable errors without reflecting rejected request values."""
        path = request.url.path
        if path.startswith("/api/v1/auth/"):
            code = "AUTH_REQUEST_INVALID"
        elif path.startswith("/api/v1/deep-scans"):
            code = "CLOUD_REQUEST_INVALID"
        else:
            code = "APP_INPUT_INVALID"

        fields = []
        for error in exc.errors():
            location = ".".join(str(part) for part in error.get("loc", ()))
            fields.append({"path": location, "type": error.get("type", "invalid")})

        return JSONResponse(
            status_code=422,
            content={
                "error": {
                    "code": code,
                    "message": "请求字段无效",
                    "retryable": False,
                    "details": {"fields": fields},
                }
            },
        )
