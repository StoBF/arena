import pytest
from decimal import Decimal
from app.services.hero import HeroService
from app.database.models.hero import Hero
from sqlalchemy.ext.asyncio import AsyncSession
import asyncio
from datetime import datetime, timedelta

@pytest.mark.asyncio
async def test_create_and_get_hero(async_session: AsyncSession):
    service = HeroService(async_session)
    name = "TestHero"
    owner_id = 1
    hero = await service.create_hero(name, owner_id)
    assert hero.name == name
    assert hero.owner_id == owner_id
    # Отримання героя
    got = await service.get_hero(hero.id)
    assert got is not None
    assert got.id == hero.id
    # Оновлення героя
    updated = await service.update_hero(hero.id, "NewName", owner_id)
    assert updated.name == "NewName"
    # Видалення героя
    deleted = await service.delete_hero(hero.id, owner_id)
    assert deleted.is_deleted is True

@pytest.mark.asyncio
def test_generate_hero_with_all_attributes(async_session):
    from app.services.hero_generation import generate_hero
    from app.core.hero_config import ATTRIBUTE_RANGES
    owner_id = 42
    gen = 5
    currency = Decimal("100")
    locale = "en"
    hero = asyncio.get_event_loop().run_until_complete(
        generate_hero(async_session, owner_id, gen, currency, locale=locale, seed=123)
    )
    attrs = ATTRIBUTE_RANGES[gen]
    assert attrs["strength"][0] <= hero.strength <= attrs["strength"][1]
    assert attrs["agility"][0] <= hero.agility <= attrs["agility"][1]
    assert attrs["intelligence"][0] <= hero.intelligence <= attrs["intelligence"][1]
    assert attrs["endurance"][0] <= hero.endurance <= attrs["endurance"][1]
    assert attrs["speed"][0] <= hero.speed <= attrs["speed"][1]
    assert attrs["health"][0] <= hero.health <= attrs["health"][1]
    assert attrs["defense"][0] <= hero.defense <= attrs["defense"][1]
    assert attrs["luck"][0] <= hero.luck <= attrs["luck"][1]
    assert attrs["field_of_view"][0] <= hero.field_of_view <= attrs["field_of_view"][1]
    assert hero.level == 1
    assert hero.experience == 0

@pytest.mark.asyncio
async def test_add_experience_and_level_up(async_session: AsyncSession):
    from app.services.hero import HeroService
    service = HeroService(async_session)
    hero = await service.create_hero("ExpHero", owner_id=123)
    hero.level = 1
    hero.experience = 0
    await async_session.commit()
    hero, leveled_up = await service.add_experience(hero.id, 200)
    assert hero.level > 1
    assert leveled_up is True
    hero, leveled_up = await service.add_experience(hero.id, 10)
    assert leveled_up is False

@pytest.mark.asyncio
async def test_get_total_stats_with_equipment(async_session: AsyncSession):
    from app.services.hero import HeroService
    from app.database.models.models import Item, Equipment
    service = HeroService(async_session)
    hero = await service.create_hero("StatHero", owner_id=321)
    item = Item(name="Sword", description="", bonus_strength=5, bonus_agility=2, bonus_intelligence=0, slot_type="weapon")
    async_session.add(item)
    await async_session.commit()
    eq = Equipment(hero_id=hero.id, item_id=item.id, slot="weapon")
    async_session.add(eq)
    await async_session.commit()
    await async_session.refresh(hero)
    stats = await service.get_total_stats(hero.id)
    assert stats["strength"] >= hero.strength + 5
    assert stats["agility"] >= hero.agility + 2

@pytest.mark.asyncio
async def test_get_nickname_for_new_attributes(async_session: AsyncSession):
    from app.services.hero import HeroService
    service = HeroService(async_session)
    hero = await service.create_hero("LuckyHero", owner_id=555)
    hero.luck = 99
    hero.strength = 10
    hero.agility = 10
    hero.intelligence = 10
    hero.endurance = 10
    hero.speed = 10
    hero.health = 10
    hero.defense = 10
    hero.field_of_view = 10
    await async_session.commit()
    nickname = service.get_nickname(hero, perks=None, locale="en")
    assert "Fortunate" in nickname or nickname == "the Fortunate"

@pytest.mark.asyncio
async def test_hero_training_flow(async_session: AsyncSession):
    from app.services.hero import HeroService
    from app.services.training import TrainingService
    from app.schemas.hero import TrainingStartRequest
    from app.database.models.hero import HeroTrainingQueue, TrainingType, TrainingStatus

    hero_service = HeroService(async_session)
    training_service = TrainingService(async_session)

    hero = await hero_service.create_hero("TrainingHero", owner_id=777)
    base_strength = hero.strength

    started = await training_service.start_training(
        hero.id,
        owner_id=777,
        req=TrainingStartRequest(
            training_type=TrainingType.ATTRIBUTE,
            training_target="strength",
            target_level=base_strength + 1,
            room_slot=0,
        ),
    )
    assert started.status == TrainingStatus.RUNNING

    entry = await async_session.get(HeroTrainingQueue, started.id)
    assert entry is not None
    entry.ends_at = datetime.utcnow() - timedelta(minutes=1)
    await async_session.commit()

    claimed = await training_service.claim_training(hero.id, owner_id=777, entry_id=started.id)
    assert claimed.status == TrainingStatus.COMPLETED

    updated_hero = await hero_service.get_hero(hero.id)
    assert updated_hero.strength == base_strength + 1
    assert updated_hero.training_sessions_completed >= 1

@pytest.mark.asyncio
async def test_upgrade_perk(async_session: AsyncSession):
    from app.services.hero import HeroService
    from app.database.models.hero import HeroPerk
    from app.database.models.perk import Perk
    service = HeroService(async_session)
    hero = await service.create_hero("PerkHero", owner_id=888)
    perk = Perk(name="Pilot", description="Test", max_level=100, modifiers={"strength": 1})
    async_session.add(perk)
    await async_session.commit()
    await async_session.refresh(perk)
    hero_perk = HeroPerk(hero_id=hero.id, perk_id=perk.id, perk_level=10)
    async_session.add(hero_perk)
    await async_session.commit()
    await async_session.refresh(hero_perk)
    upgraded = await service.upgrade_perk(hero.id, perk.id, user_id=888)
    assert upgraded.perk_level == 11
    upgraded.perk_level = 100
    await async_session.commit()
    with pytest.raises(Exception):
        await service.upgrade_perk(hero.id, perk.id, user_id=888)
    with pytest.raises(Exception):
        await service.upgrade_perk(hero.id, 9999, user_id=888) 