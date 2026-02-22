from fastapi import APIRouter, Depends, HTTPException, Body, Request, Response
from sqlalchemy.ext.asyncio import AsyncSession
from app.database.session import get_session
from app.schemas.user import UserCreate, UserLogin, UserOut, TokenResponse, TokenRefreshResponse
from app.services.auth import AuthService
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
import logging

router = APIRouter()
logger = logging.getLogger(__name__)

limiter = Limiter(key_func=get_remote_address)

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
        raise HTTPException(status_code=400, detail="User already exists")
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
    
    # Set refresh token in HTTP-only secure cookie (more secure than including in response body)
    # HttpOnly prevents JavaScript from accessing it
    # Secure only sends over HTTPS
    # SameSite=Strict prevents CSRF attacks
    response.set_cookie(
        key="refresh_token",
        value=tokens["refresh_token"],
        max_age=7 * 24 * 60 * 60,  # 7 days
        httponly=True,              # Prevent JavaScript access
        secure=True,                # Only send over HTTPS in production
        samesite="strict"           # CSRF protection
    )
    
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
    email = google_token  # In production, parse through Google API
    user = await AuthService(db).get_user_by_email_or_username(email)
    if not user:
        user = await AuthService(db).create_user(email=email, username=None, password=None, is_google=True)
    
    tokens = AuthService(db).generate_tokens(user)
    
    # Set refresh token in HTTP-only secure cookie
    response.set_cookie(
        key="refresh_token",
        value=tokens["refresh_token"],
        max_age=7 * 24 * 60 * 60,  # 7 days
        httponly=True,
        secure=True,
        samesite="strict"
    )
    
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
    # Read refresh token from HTTP-only cookie
    refresh_token_cookie = request.cookies.get("refresh_token")
    
    if not refresh_token_cookie:
        logger.warning(f"[AUTH_REFRESH_FAILED] no_refresh_token_in_cookie")
        raise HTTPException(status_code=401, detail="Refresh token not found in cookie")
    
    # Validate and create new tokens (with token rotation)
    result = AuthService(db).refresh_access_token(refresh_token_cookie)
    
    if not result:
        logger.warning(f"[AUTH_REFRESH_FAILED] invalid_refresh_token")
        raise HTTPException(status_code=401, detail="Invalid refresh token")
    
    # Set NEW refresh token in HTTP-only cookie (token rotation)
    # This invalidates the old cookie and provides a new one
    response.set_cookie(
        key="refresh_token",
        value=result["refresh_token"],
        max_age=7 * 24 * 60 * 60,  # 7 days
        httponly=True,              # Prevent JavaScript access
        secure=True,                # Only send over HTTPS in production
        samesite="strict"           # CSRF protection
    )
    
    logger.info(f"[AUTH_REFRESH_SUCCESS] user_id={result.get('user_id')} family={result.get('family')}")
    
    # Return new access token to client
    return {
        "access_token": result["access_token"],
        "token_type": "bearer"
    }
