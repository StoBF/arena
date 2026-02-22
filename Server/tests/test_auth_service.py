import pytest
from app.services.auth import AuthService
from app.database.models.user import User
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.database.session import Base
import asyncio

DATABASE_URL = "sqlite+aiosqlite:///:memory:"

@pytest.fixture(scope="module")
def event_loop():
    loop = asyncio.get_event_loop()
    yield loop

@pytest.fixture(scope="module")
async def db():
    engine = create_async_engine(DATABASE_URL, echo=False)
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with async_session() as session:
        yield session
    await engine.dispose()

@pytest.mark.asyncio
async def test_create_and_authenticate_user(db):
    service = AuthService(db)
    email = "test@example.com"
    username = "testuser"
    password = "testpass123"
    user = await service.create_user(email, username, password)
    assert user.email == email
    assert user.username == username
    # Аутентифікація
    auth_user = await service.authenticate_user(email, password)
    assert auth_user is not None
    assert auth_user.email == email
    # Генерація токенів
    tokens = service.generate_tokens(user)
    assert "access_token" in tokens
    assert "refresh_token" in tokens
    # Оновлення access токена
    new_access = service.refresh_access_token(tokens["refresh_token"])
    assert isinstance(new_access, str) 