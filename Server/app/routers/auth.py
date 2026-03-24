from fastapi import APIRouter, Depends, HTTPException, Body, Request, Response
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests
from sqlalchemy.ext.asyncio import AsyncSession
from app.database.session import get_session
from app.schemas.user import UserCreate, UserLogin, UserOut, UserWithBalance, TokenResponse, TokenRefreshResponse
from app.services.auth import AuthService
from app.auth import get_current_user
from app.core.config import settings
from app.services.session_registry import active_session_registry
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
import logging

router = APIRouter()
logger = logging.getLogger(__name__)

limiter = Limiter(key_func=get_remote_address)


def _set_refresh_cookie(response: Response, refresh_token: str) -> None:
    """
    Centralized refresh cookie configuration.
    Uses environment-driven flags so local HTTP development works on Windows,
    while production can enforce secure cookies.
    """
    response.set_cookie(
        key="refresh_token",
        value=refresh_token,
        max_age=7 * 24 * 60 * 60,
        httponly=True,
        secure=settings.COOKIE_SECURE,
        samesite=settings.COOKIE_SAMESITE,
    )


def _extract_refresh_token(request: Request, body_token: str | None) -> str | None:
    """
    Refresh token lookup order:
    1) HTTP-only cookie (preferred)
    2) JSON body token (for native clients)
    3) Authorization: Bearer <refresh_token>
    """
    token = request.cookies.get("refresh_token")
    if token:
        return token

    if body_token:
        return body_token

    auth_header = request.headers.get("Authorization", "")
    if auth_header.lower().startswith("bearer "):
        return auth_header.split(" ", 1)[1].strip() or None

    return None


def _extract_access_token(request: Request) -> str | None:
    auth_header = request.headers.get("Authorization", "")
    if auth_header.lower().startswith("bearer "):
        token = auth_header.split(" ", 1)[1].strip()
        return token or None
    return None

@router.post(
    "/register",
    response_model=UserOut,
    summary="Register a new user",
    description="Registers a new user with email, username, and password. Returns the created user. Rate limited to 5 requests per minute."
)
@limiter.limit("5/minute")
async def register(user: UserCreate, request: Request, db: AsyncSession = Depends(get_session)):
    existing = await AuthService(db).get_user_by_email_or_username(user.email)
    if existing:
        raise HTTPException(status_code=400, detail="User with this email already exists")
    existing_username = await AuthService(db).get_user_by_email_or_username(user.username)
    if existing_username:
        raise HTTPException(status_code=400, detail="Username already taken")
    new_user = await AuthService(db).create_user(user.email, user.username, user.password)
    return new_user

@router.post(
    "/login",
    response_model=TokenResponse,
    summary="User login",
    description="Authenticates a user with email/username and password. Returns access token in response body and refresh token in HTTP-only secure cookie."
)
@limiter.limit("5/minute")
async def login(login_data: UserLogin, request: Request, response: Response, db: AsyncSession = Depends(get_session)):
    user = await AuthService(db).authenticate_user(login_data.login, login_data.password)
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")
    
    tokens = AuthService(db).generate_tokens(user)
    active_session_registry.register_access_token(tokens["access_token"])
    
    # Set refresh token in HTTP-only secure cookie (more secure than including in response body)
    # HttpOnly prevents JavaScript from accessing it
    # Secure only sends over HTTPS
    # SameSite=Strict prevents CSRF attacks
    _set_refresh_cookie(response, tokens["refresh_token"])
    
    logger.info(f"[AUTH_LOGIN_SUCCESS] user_id={user.id} family={tokens.get('family')}")
    
    # Return only access token to client (refresh token is in cookie)
    return {
        "access_token": tokens["access_token"],
        "refresh_token": tokens["refresh_token"],  # Also in response for clients that need it
        "token_type": "bearer"
    }

@router.post(
    "/google-login",
    response_model=TokenResponse,
    summary="Login with Google",
    description="Authenticates a user via Google OAuth. If the user does not exist, creates a new account. Returns access token in response body and refresh token in HTTP-only secure cookie."
)
@limiter.limit("5/minute")
async def google_login(request: Request, response: Response, google_token: str = Body(...), db: AsyncSession = Depends(get_session)):
    try:
        # Specify CLIENT_ID if you want to verify aud claim, else None
        idinfo = id_token.verify_oauth2_token(google_token, google_requests.Request(), None)
        email = idinfo.get("email")
        if not email:
            raise ValueError("No email in Google token")
    except Exception as e:
        logger.warning(f"[AUTH_GOOGLE_LOGIN_FAIL] Invalid Google token: {e}")
        raise HTTPException(status_code=401, detail="Invalid Google ID token")

    user = await AuthService(db).get_user_by_email_or_username(email)
    if not user:
        base_username = email.split("@")[0]
        user = await AuthService(db).create_user(email=email, username=base_username, password=None, is_google=True)

    tokens = AuthService(db).generate_tokens(user)
    active_session_registry.register_access_token(tokens["access_token"])

    _set_refresh_cookie(response, tokens["refresh_token"])
    logger.info(f"[AUTH_GOOGLE_LOGIN_SUCCESS] user_id={user.id} family={tokens.get('family')}")
    return {
        "access_token": tokens["access_token"],
        "refresh_token": tokens["refresh_token"],
        "token_type": "bearer"
    }

@router.post(
    "/refresh",
    response_model=TokenRefreshResponse,
    summary="Refresh access token",
    description="Refreshes the access token using refresh token from HTTP-only cookie. Returns new access token and sets new refresh token in cookie."
)
@limiter.limit("5/minute")
async def refresh_token(request: Request, response: Response, db: AsyncSession = Depends(get_session)):
    # Accept token from cookie (preferred), request body, or Authorization header.
    body: dict | None = None
    if request.headers.get("content-type", "").startswith("application/json"):
        try:
            parsed = await request.json()
            if isinstance(parsed, dict):
                body = parsed
        except Exception:
            body = None
    body_token = body.get("refresh_token") if isinstance(body, dict) else None
    refresh_token_cookie = _extract_refresh_token(request, body_token)
    
    if not refresh_token_cookie:
        logger.warning(f"[AUTH_REFRESH_FAILED] no_refresh_token_provided")
        raise HTTPException(status_code=401, detail="Refresh token not provided")
    
    # Validate and create new tokens (with token rotation)
    result = AuthService(db).refresh_access_token(refresh_token_cookie)
    
    if not result:
        logger.warning(f"[AUTH_REFRESH_FAILED] invalid_refresh_token")
        raise HTTPException(status_code=401, detail="Refresh token invalid or expired")
    
    # Set NEW refresh token in HTTP-only cookie (token rotation)
    # This invalidates the old cookie and provides a new one
    _set_refresh_cookie(response, result["refresh_token"])
    active_session_registry.register_access_token(result["access_token"])

    old_access_token = _extract_access_token(request)
    if old_access_token:
        active_session_registry.unregister_access_token(old_access_token)
    
    logger.info(f"[AUTH_REFRESH_SUCCESS] user_id={result.get('user_id')} family={result.get('family')}")
    
    # Return new access token to client
    return {
        "access_token": result["access_token"],
        "token_type": "bearer"
    }


@router.post(
    "/logout",
    summary="User logout",
    description="Logs out current user, clears refresh cookie, and removes active access token from in-memory registry."
)
async def logout(request: Request, response: Response, _user=Depends(get_current_user)):
    access_token = _extract_access_token(request)
    if access_token:
        active_session_registry.unregister_access_token(access_token)

    response.delete_cookie(
        key="refresh_token",
        httponly=True,
        secure=settings.COOKIE_SECURE,
        samesite=settings.COOKIE_SAMESITE,
    )
    return {"status": "ok"}


@router.get(
    "/me",
    response_model=UserWithBalance,
    summary="Get current user profile",
    description="Returns the authenticated user's profile including username and balance."
)
async def get_me(user=Depends(get_current_user)):
    return user
