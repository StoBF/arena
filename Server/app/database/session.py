# app/database/session.py
from app.database.base import Base
import app.database.models  # noqa: F401 - imports all model modules and registers metadata
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.pool import StaticPool
from sqlalchemy.orm import sessionmaker
from app.core.config import settings
from typing import AsyncGenerator

DATABASE_URL = settings.DATABASE_URL

# Build engine kwargs — SQLite needs special connect_args;
# PostgreSQL / other databases use connection-pool defaults.
_engine_kwargs: dict = {
    "echo": False,
    "future": True,
}
if DATABASE_URL.startswith("sqlite"):
    _engine_kwargs["connect_args"] = {"check_same_thread": False}
    _engine_kwargs["poolclass"] = StaticPool

engine = create_async_engine(DATABASE_URL, **_engine_kwargs)

AsyncSessionLocal = sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False
)

async def create_db_and_tables():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

async def get_session() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        yield session

get_async_session = get_session

# Monkey-patch AsyncSession to support add_all for compatibility with tests
def _async_add_all(self, entities):
    """Add multiple instances to the session."""
    for entity in entities:
        self.add(entity)
AsyncSession.add_all = _async_add_all
