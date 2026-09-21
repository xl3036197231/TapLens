from datetime import UTC, datetime
from uuid import uuid4

from app.auth.passwords import DUMMY_PASSWORD_HASH, PasswordService
from app.auth.schemas import TokenResponse, UserResponse
from app.auth.tokens import TokenService
from app.core.errors import AppError
from app.storage.users import DuplicateUsernameError, UserRecord, UserRepository


class AuthService:
    def __init__(
        self,
        *,
        users: UserRepository,
        passwords: PasswordService,
        tokens: TokenService,
    ) -> None:
        self.users = users
        self.passwords = passwords
        self.tokens = tokens

    def register(self, username: str, password: str) -> UserResponse:
        normalized = normalize_username(username)
        user = UserRecord(
            id=uuid4(),
            username=username,
            username_normalized=normalized,
            password_hash=self.passwords.hash(password),
            created_at=datetime.now(UTC),
        )
        try:
            self.users.create(user)
        except DuplicateUsernameError as exc:
            raise AppError(
                code="AUTH_USERNAME_TAKEN",
                message="用户名已被使用",
                status_code=409,
            ) from exc
        return to_user_response(user)

    def login(self, username: str, password: str) -> TokenResponse:
        user = self.users.find_by_normalized_username(normalize_username(username))
        stored_hash = user.password_hash if user is not None else DUMMY_PASSWORD_HASH
        password_matches = self.passwords.verify(stored_hash, password)
        if user is None or not password_matches:
            raise AppError(
                code="AUTH_INVALID_CREDENTIALS",
                message="用户名或密码错误",
                status_code=401,
            )

        token, expires_at = self.tokens.issue_access_token(user.id)
        return TokenResponse(
            access_token=token,
            expires_at=expires_at,
            user=to_user_response(user),
        )


def normalize_username(username: str) -> str:
    return username.casefold()


def to_user_response(user: UserRecord) -> UserResponse:
    return UserResponse(
        user_id=user.id,
        username=user.username,
        created_at=user.created_at,
    )
