from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database.models.user import User
from passlib.context import CryptContext
from app.utils.jwt import create_access_token, create_refresh_token, decode_refresh_token
from app.services.base_service import BaseService
from app.core.config import settings
import logging

logger = logging.getLogger(__name__)
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

class AuthService(BaseService):
    async def get_user_by_email_or_username(self, login: str):
        query = select(User).where((User.email == login) | (User.username == login))
        result = await self.session.execute(query)
        return result.scalars().first()

    async def create_user(self, email: str, username: str | None, password: str | None, is_google: bool = False):
        hashed_password = pwd_context.hash(password) if password else None
        new_user = User(
            email=email,
            username=username,
            hashed_password=hashed_password,
            is_google_account=is_google
        )
        self.session.add(new_user)
        await self.commit_or_rollback()
        await self.session.refresh(new_user)
        return new_user

    async def authenticate_user(self, login: str, password: str):
        user = await self.get_user_by_email_or_username(login)
        if user and user.hashed_password and pwd_context.verify(password, user.hashed_password):
            return user
        return None

    def generate_tokens(self, user: User, family_id: str | None = None):
        """Generate access and refresh tokens with token rotation support
        
        Args:
            user: User object
            family_id: Optional rotation family ID for token rotation chains
        
        Returns:
            Dict with access_token, refresh_token, family, and token_type
        """
        token_data = {"sub": str(user.id), "role": user.role}
        
        # Generate short-lived access token (20 min by default)
        access = create_access_token(token_data)
        
        # Generate long-lived refresh token (7 days by default) with rotation family
        refresh, rotation_family = create_refresh_token(token_data, family_id=family_id)
        
        logger.info(f"[AUTH_TOKENS_GENERATED] user_id={user.id} family={rotation_family}")
        
        return {
            "access_token": access,
            "refresh_token": refresh,
            "token_type": "bearer",
            "family": rotation_family
        }

    def refresh_access_token(self, refresh_token: str):
        """Refresh access token using valid refresh token with token rotation
        
        Validates refresh token and returns new access token + new refresh token.
        The new refresh token uses same family ID for rotation tracking.
        
        Returns:
            Dict with new access_token, refresh_token, family, and token_type, or None if invalid
        """
        payload = decode_refresh_token(refresh_token)
        if not payload or "sub" not in payload or "role" not in payload:
            logger.warning(f"[AUTH_REFRESH_FAILED] invalid_refresh_token")
            return None
        
        user_id = payload["sub"]
        role = payload["role"]
        family_id = payload.get("family")  # Extract rotation family
        
        # Create new access token
        new_access = create_access_token({"sub": user_id, "role": role})
        
        # Create new refresh token with SAME family ID (token rotation)
        # This maintains the token family chain for compromise detection
        new_refresh, _ = create_refresh_token(
            {"sub": user_id, "role": role},
            family_id=family_id
        )
        
        logger.info(f"[AUTH_TOKEN_REFRESHED] user_id={user_id} family={family_id}")
        
        return {
            "access_token": new_access,
            "refresh_token": new_refresh,
            "token_type": "bearer",
            "family": family_id
        }

# Module-level wrapper for compatibility: allow direct import of functions from the module
async def get_user_by_email_or_username(session: AsyncSession, identifier: str):
    """Get a user by email or username using AuthService internally"""
    return await AuthService(session).get_user_by_email_or_username(identifier)
