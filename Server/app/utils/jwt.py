from datetime import datetime, timedelta
from jose import jwt, JWTError
from app.core.config import settings
import uuid

def create_access_token(data: dict, expires_delta: timedelta | None = None):
    """Create a short-lived access token (default: 20 minutes)"""
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.utcnow() + expires_delta
    else:
        expire = datetime.utcnow() + timedelta(minutes=settings.JWT_ACCESS_TOKEN_MINUTES)
    to_encode.update({"exp": expire, "type": "access"})
    encoded_jwt = jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)
    return encoded_jwt

def decode_access_token(token: str):
    """Decode and validate access token"""
    try:
        payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
        if payload.get("type") != "access":
            return None
        return payload
    except JWTError:
        return None

def create_refresh_token(data: dict, family_id: str | None = None):
    """Create a long-lived refresh token (default: 7 days) with token rotation family
    
    Token rotation family allows us to track refresh token chains and detect reuse.
    If same family_id is used twice, it indicates token compromise.
    """
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(days=settings.JWT_REFRESH_TOKEN_DAYS)
    
    # Generate unique family ID for this token chain (or use provided)
    rotation_family = family_id or str(uuid.uuid4())
    
    to_encode.update({
        "exp": expire,
        "type": "refresh",
        "family": rotation_family  # Track token family for rotation detection
    })
    encoded_jwt = jwt.encode(to_encode, settings.JWT_SECRET_KEY, algorithm=settings.JWT_ALGORITHM)
    return encoded_jwt, rotation_family

def decode_refresh_token(token: str):
    """Decode and validate refresh token"""
    try:
        payload = jwt.decode(token, settings.JWT_SECRET_KEY, algorithms=[settings.JWT_ALGORITHM])
        if payload.get("type") != "refresh":
            return None
        return payload
    except JWTError:
        return None


def get_user_id_from_token(token: str) -> int | None:
    """Helper used by WebSocket handlers.

    Decodes access token and returns integer user_id, or ``None`` if invalid.
    """
    try:
        payload = decode_access_token(token)
        if not payload:
            return None
        return int(payload.get("sub"))
    except Exception:
        return None
