from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import jwt


class TokenService:
    def __init__(self, *, secret: str, access_token_minutes: int) -> None:
        self.secret = secret
        self.access_token_minutes = access_token_minutes

    def issue_access_token(self, user_id: UUID, now: datetime | None = None) -> tuple[str, datetime]:
        issued_at = now or datetime.now(UTC)
        expires_at = issued_at + timedelta(minutes=self.access_token_minutes)
        payload = {
            "sub": str(user_id),
            "type": "access",
            "jti": str(uuid4()),
            "iat": issued_at,
            "exp": expires_at,
        }
        return jwt.encode(payload, self.secret, algorithm="HS256"), expires_at

    def decode_access_token(self, token: str) -> UUID:
        payload = jwt.decode(
            token,
            self.secret,
            algorithms=["HS256"],
            options={"require": ["sub", "type", "jti", "iat", "exp"]},
        )
        if payload.get("type") != "access":
            raise jwt.InvalidTokenError("unexpected token type")
        return UUID(payload["sub"])
