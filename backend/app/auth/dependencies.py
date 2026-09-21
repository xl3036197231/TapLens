from uuid import UUID

import jwt
from fastapi import Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.auth.tokens import TokenService
from app.core.errors import AppError
from app.storage.users import UserRepository


bearer_scheme = HTTPBearer(auto_error=False)


def current_user_id(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = None,
) -> UUID:
    if credentials is None:
        raise AppError(
            code="AUTH_TOKEN_MISSING",
            message="请先登录",
            status_code=401,
        )

    settings = request.app.state.settings
    tokens = TokenService(
        secret=settings.jwt_secret.get_secret_value(),
        access_token_minutes=settings.access_token_minutes,
    )
    try:
        user_id = tokens.decode_access_token(credentials.credentials)
    except jwt.ExpiredSignatureError as exc:
        raise AppError(
            code="AUTH_TOKEN_EXPIRED",
            message="登录已过期，请重新登录",
            status_code=401,
        ) from exc
    except (jwt.InvalidTokenError, ValueError) as exc:
        raise AppError(
            code="AUTH_TOKEN_INVALID",
            message="登录凭证无效",
            status_code=401,
        ) from exc

    if UserRepository(request.app.state.database).find_by_id(user_id) is None:
        raise AppError(
            code="AUTH_TOKEN_INVALID",
            message="登录凭证无效",
            status_code=401,
        )
    return user_id
