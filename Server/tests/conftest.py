import pytest
import pytest_asyncio
import httpx
from decimal import Decimal
from httpx import AsyncClient as _AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.session import get_async_session, create_db_and_tables
from app.database.models.user import User
from app.database.models.craft import CraftedItem
from app.main import app
from app.utils.jwt import create_access_token

# Monkey-patch httpx.AsyncClient to accept 'app' for ASGITransport
class AsyncClient(_AsyncClient):
    def __init__(self, *args, app=None, transport=None, **kwargs):
        if app is not None:
            transport = ASGITransport(app=app)
        super().__init__(*args, transport=transport, **kwargs)

httpx.AsyncClient = AsyncClient

@pytest_asyncio.fixture(scope="session", autouse=True)
async def init_db():
    # Create database tables before any tests run
    await create_db_and_tables()

@pytest_asyncio.fixture
async def async_session() -> AsyncSession:
    # Provide a fresh AsyncSession for each test
    async for session in get_async_session():
        yield session

@pytest_asyncio.fixture
async def test_user(async_session: AsyncSession):
    # create a fresh user each time to avoid uniqueness conflicts
    from uuid import uuid4
    suffix = uuid4().hex[:8]
    user = User(
        username=f"testuser_{suffix}",
        email=f"test{suffix}@example.com",
        balance=Decimal("1000"),
        reserved=Decimal("0"),
    )
    async_session.add(user)
    await async_session.flush()
    return user

@pytest_asyncio.fixture
async def test_user_token(test_user: User):
    # Issue JWT for test user
    return create_access_token({"sub": str(test_user.id), "role": test_user.role})

@pytest_asyncio.fixture
async def other_user_crafted_item_id(async_session: AsyncSession):
    # Create a second user and a crafted item for them
    other = User(username="otheruser", email="other@example.com", balance=Decimal("1000"), reserved=Decimal("0"))
    async_session.add(other)
    await async_session.flush()
    crafted = CraftedItem(
        user_id=other.id,
        result_item_id=None,
        item_type="material",
        grade=1,
        recipe_id=1,
    )
    async_session.add(crafted)
    await async_session.commit()
    return crafted.id

@pytest_asyncio.fixture
async def test_client():
    # HTTP client bound to our FastAPI app
    async with AsyncClient(app=app, base_url="http://testserver") as client:
        yield client
