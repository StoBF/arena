import pytest
import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.database.session import Base
from app.database.models.hero import Hero
from sqlalchemy import select
from app.database.models.models import Item, Stash, SlotType
from app.services.equipment import EquipmentService

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
async def test_equip_and_unequip(db):
    # Створюємо користувача і героя
    from app.database.models.user import User
    user = User(username="testuser", email="test@example.com")
    db.add(user)
    await db.commit()
    await db.refresh(user)
    hero = Hero(name="Hero", owner_id=user.id, primary_role="VANGUARD", locale="en")
    db.add(hero)
    await db.commit()
    await db.refresh(hero)
    # Створюємо предмет у складі
    item = Item(name="Laser Sword", description="", type="weapon", slot_type="weapon", bonus_strength=5)
    db.add(item)
    await db.commit()
    await db.refresh(item)
    stash = Stash(user_id=user.id, item_id=item.id, quantity=1)
    db.add(stash)
    await db.commit()
    await db.refresh(stash)
    # Екіпіруємо предмет
    service = EquipmentService(db)
    eq = await service.equip_item(hero_id=hero.id, user_id=user.id, item_id=item.id, slot=SlotType.weapon)
    assert eq.hero_id == hero.id
    assert eq.item_id == item.id
    # Перевіряємо, що предмет зник зі складу
    stash = (await db.execute(
        select(Stash).where(Stash.user_id == user.id, Stash.item_id == item.id)
    )).scalars().first()
    assert stash is None or stash.quantity == 0
    # Знімаємо екіпіровку
    result = await service.unequip_item(hero_id=hero.id, user_id=user.id, slot=SlotType.weapon)
    assert result is True
    # Перевіряємо, що предмет повернувся у склад
    stash = (await db.execute(
        select(Stash).where(Stash.user_id == user.id, Stash.item_id == item.id)
    )).scalars().first()
    assert stash is not None and stash.quantity == 1

@pytest.mark.asyncio
async def test_equip_invalid_slot(db):
    from app.database.models.user import User
    user = User(username="slotuser", email="slot@example.com")
    db.add(user)
    await db.commit()
    await db.refresh(user)
    hero = Hero(name="SlotHero", owner_id=user.id, primary_role="VANGUARD", locale="en")
    db.add(hero)
    await db.commit()
    await db.refresh(hero)
    item = Item(name="Helmet", description="", type="helmet", slot_type="helmet")
    db.add(item)
    await db.commit()
    await db.refresh(item)
    stash = Stash(user_id=user.id, item_id=item.id, quantity=1)
    db.add(stash)
    await db.commit()
    await db.refresh(stash)
    service = EquipmentService(db)
    # Спроба екіпірувати у неіснуючий слот
    with pytest.raises(Exception):
        await service.equip_item(hero_id=hero.id, user_id=user.id, item_id=item.id, slot=SlotType.not_a_slot)
    # Спроба екіпірувати у неправильний слот
    with pytest.raises(Exception):
        await service.equip_item(hero_id=hero.id, user_id=user.id, item_id=item.id, slot=SlotType.weapon) 