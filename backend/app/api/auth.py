from fastapi import APIRouter, Request, status

from app.auth.passwords import PasswordService
from app.auth.schemas import CredentialsRequest, TokenResponse, UserResponse
from app.auth.service import AuthService
from app.auth.tokens import TokenService
from app.storage.users import UserRepository


router = APIRouter(prefix="/auth", tags=["authentication"])


def auth_service(request: Request) -> AuthService:
    settings = request.app.state.settings
    return AuthService(
        users=UserRepository(request.app.state.database),
        passwords=PasswordService(),
        tokens=TokenService(
            secret=settings.jwt_secret.get_secret_value(),
            access_token_minutes=settings.access_token_minutes,
        ),
    )


@router.post("/register", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def register(payload: CredentialsRequest, request: Request) -> UserResponse:
    return auth_service(request).register(payload.username, payload.password)


@router.post("/login", response_model=TokenResponse)
def login(payload: CredentialsRequest, request: Request) -> TokenResponse:
    return auth_service(request).login(payload.username, payload.password)
