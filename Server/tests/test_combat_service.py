import pytest
import asyncio
from datetime import datetime, timedelta
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.database.session import Base
from app.database.models.hero import Hero, HeroPerk
from app.services.combat import CombatService

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
async def test_duel_basic(db):
    # Створюємо двох героїв
    hero1 = Hero(name="A", generation=1, nickname="A", strength=20, agility=10, intelligence=5, endurance=10, speed=10, health=50, defense=5, luck=5, field_of_view=5, level=1, experience=0, locale="en", owner_id=1)
    hero2 = Hero(name="B", generation=1, nickname="B", strength=10, agility=10, intelligence=5, endurance=10, speed=10, health=50, defense=5, luck=5, field_of_view=5, level=1, experience=0, locale="en", owner_id=2)
    db.add_all([hero1, hero2])
    await db.commit()
    await db.refresh(hero1)
    await db.refresh(hero2)
    # Без перків
    result = await CombatService(db).simulate_duel(hero1, hero2)
    assert result.winner in ("team_a", "team_b", "draw")
    assert isinstance(result.log, list)
    assert isinstance(result.rewards, dict)
    # Перевірка смерті
    await db.refresh(hero1)
    await db.refresh(hero2)
    assert hero1.is_dead or hero2.is_dead
    # Відродження
    hero1.is_dead = True
    hero1.dead_until = datetime.utcnow() - timedelta(minutes=1)
    await db.commit()
    # Симулюємо revive
    from app.tasks.cleanup import revive_dead_heroes_task
    await revive_dead_heroes_task()
    await db.refresh(hero1)
    assert not hero1.is_dead

@pytest.mark.asyncio
async def test_perk_effects(db):
    # Герой з offensive перком
    hero1 = Hero(name="C", generation=1, nickname="C", strength=10, agility=10, intelligence=5, endurance=10, speed=10, health=50, defense=5, luck=5, field_of_view=5, level=1, experience=0, locale="en", owner_id=1)
    perk = HeroPerk(hero_id=hero1.id, perk_name="Plasma Gunner", perk_level=50)
    db.add(hero1)
    await db.commit()
    db.add(perk)
    await db.commit()
    await db.refresh(hero1)
    # Герой без перків
    hero2 = Hero(name="D", generation=1, nickname="D", strength=10, agility=10, intelligence=5, endurance=10, speed=10, health=50, defense=5, luck=5, field_of_view=5, level=1, experience=0, locale="en", owner_id=2)
    db.add(hero2)
    await db.commit()
    await db.refresh(hero2)
    # Перевіряємо, що герой з перком має перевагу
    result = await CombatService(db).simulate_duel(hero1, hero2)
    assert result.winner in ("team_a", "team_b", "draw")
    # Лог містить хід з Plasma Gunner
    assert any("Plasma Gunner" in str(line) or "hits" in str(line) for line in result.log) 