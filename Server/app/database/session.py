# app/database/session.py
from app.database.base import Base
import app.database.models.hero
import app.database.models.user
import app.database.models.models
import app.database.models.perk
import app.database.models.craft
import app.database.models.resource
import app.database.models.pve
import app.database.models.raid_boss
import app.database.models.tournament
import app.database.models.event
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.pool import StaticPool
from sqlalchemy.orm import sessionmaker
from app.core.config import settings
from typing import AsyncGenerator

DATABASE_URL = settings.DATABASE_URL
# Always use in-memory SQLite engine for app sessions to avoid external DB connections
engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    future=True,
    connect_args={"check_same_thread": False},
    poolclass=StaticPool
)

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
