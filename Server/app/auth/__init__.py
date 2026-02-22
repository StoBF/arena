from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from sqlalchemy.ext.asyncio import AsyncSession
from app.database.session import get_session
from app.database.models.user import User
from app.utils.jwt import decode_access_token
from sqlalchemy.future import select

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/login")

async def get_current_user_info(token: str = Depends(oauth2_scheme)):
    payload = decode_access_token(token)
    if not payload or "sub" not in payload or "role" not in payload:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user_id = int(payload["sub"])
    return {"user_id": user_id, "role": payload["role"]}

async def get_current_user(
    required_role: str = "user",
    token: str = Depends(oauth2_scheme),
    session: AsyncSession = Depends(get_session),
):
    """
    Повертає повний об'єкт User з БД. Якщо потрібен лише user_id/role, використовуйте get_current_user_info.
    """
    payload = decode_access_token(token)
    if not payload or "sub" not in payload or "role" not in payload:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    user_id = int(payload["sub"])
    role = payload["role"]
    if required_role == "admin" and role != "admin":
        raise HTTPException(status_code=403, detail="Admin privileges required")
    if required_role == "moderator" and role not in ("admin", "moderator"):
        raise HTTPException(status_code=403, detail="Moderator privileges required")
    # Отримати користувача з БД
    result = await session.execute(select(User).where(User.id == user_id))
    user = result.scalars().first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

# Псевдонім для залежності (щоб не ламати старий код)
authenticated_user = get_current_user 