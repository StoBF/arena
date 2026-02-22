import pytest
import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.database.session import Base
from app.database.models.models import Item, Stash
from app.database.models.user import User
from app.services.inventory import StashService

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
async def test_add_and_remove_stash(db):
    user = User(username="stashuser", email="stash@example.com")
    db.add(user)
    await db.commit()
    await db.refresh(user)
    item = Item(name="Nano Battery", description="", type="resource", slot_type="gadget")
    db.add(item)
    await db.commit()
    await db.refresh(item)
    service = StashService(db)
    # Додаємо 2 предмети
    stash = await service.add_to_stash(user_id=user.id, item_id=item.id, quantity=2)
    assert stash.quantity == 2
    # Додаємо ще 3 (агрегація)
    stash = await service.add_to_stash(user_id=user.id, item_id=item.id, quantity=3)
    assert stash.quantity == 5
    # Видаляємо 2
    result = await service.remove_from_stash(user_id=user.id, item_id=item.id, quantity=2)
    assert result is True
    stash = await service.get_stash_item(stash.id)
    assert stash.quantity == 3
    # Видаляємо всі
    result = await service.remove_from_stash(user_id=user.id, item_id=item.id, quantity=3)
    assert result is True
    stash = await service.get_stash_item(stash.id)
    assert stash is None

@pytest.mark.asyncio
async def test_stash_uniqueness(db):
    user = User(username="uniqueuser", email="unique@example.com")
    db.add(user)
    await db.commit()
    await db.refresh(user)
    item1 = Item(name="Plasma Core", description="", type="resource", slot_type="gadget")
    item2 = Item(name="Quantum Chip", description="", type="resource", slot_type="gadget")
    db.add_all([item1, item2])
    await db.commit()
    await db.refresh(item1)
    await db.refresh(item2)
    service = StashService(db)
    # Додаємо різні предмети
    stash1 = await service.add_to_stash(user_id=user.id, item_id=item1.id, quantity=1)
    stash2 = await service.add_to_stash(user_id=user.id, item_id=item2.id, quantity=2)
    assert stash1.item_id != stash2.item_id
    # Додаємо ще раз той самий item1
    stash1b = await service.add_to_stash(user_id=user.id, item_id=item1.id, quantity=4)
    assert stash1b.id == stash1.id
    assert stash1b.quantity == 5 