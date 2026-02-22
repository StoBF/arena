import pytest
from datetime import datetime, timedelta
from sqlalchemy.ext.asyncio import AsyncSession
from app.database.models.craft import CraftRecipe, CraftedItem, CraftQueue, CraftRecipeResource
from app.database.models.models import Stash, Item, ItemType, SlotType
from app.services.craft import CraftService

@pytest.mark.asyncio
async def test_can_craft_enough_resources(async_session: AsyncSession, test_user):
    recipe = CraftRecipe(name="Test Sword", item_type="weapon", grade=1, craft_time_sec=10)
    async_session.add(recipe)
    await async_session.flush()
    resource = CraftRecipeResource(recipe_id=recipe.id, resource_id=201, quantity=2, type="pve")
    async_session.add(resource)
    await async_session.flush()
    stash = Stash(user_id=test_user.id, item_id=201, quantity=5)
    async_session.add(stash)
    await async_session.flush()
    service = CraftService(async_session)
    can_craft = await service.can_craft(test_user.id, recipe)
    assert can_craft

@pytest.mark.asyncio
async def test_can_craft_not_enough_resources(async_session: AsyncSession, test_user):
    recipe = CraftRecipe(name="Test Shield", item_type="armor", grade=1, craft_time_sec=10)
    async_session.add(recipe)
    await async_session.flush()
    resource = CraftRecipeResource(recipe_id=recipe.id, resource_id=202, quantity=3, type="pvp")
    async_session.add(resource)
    await async_session.flush()
    stash = Stash(user_id=test_user.id, item_id=202, quantity=2)
    async_session.add(stash)
    await async_session.flush()
    service = CraftService(async_session)
    can_craft = await service.can_craft(test_user.id, recipe)
    assert not can_craft

@pytest.mark.asyncio
async def test_start_and_finish_craft(async_session: AsyncSession, test_user):
    item = Item(name="Potion", description="", type=ItemType.consumable, slot_type=SlotType.artifact, bonus_strength=0)
    async_session.add(item)
    await async_session.flush()
    recipe = CraftRecipe(name="Test Potion", item_type="consumable", grade=1, craft_time_sec=0, result_item_id=item.id)
    async_session.add(recipe)
    await async_session.flush()
    resource = CraftRecipeResource(recipe_id=recipe.id, resource_id=203, quantity=1, type="pve")
    async_session.add(resource)
    await async_session.flush()
    stash = Stash(user_id=test_user.id, item_id=203, quantity=1)
    async_session.add(stash)
    await async_session.flush()
    service = CraftService(async_session)
    queue = await service.start_craft(test_user.id, recipe.id)
    crafted = await service.finish_craft(queue.id)
    assert crafted.recipe_id == recipe.id
    assert crafted.result_item_id == item.id

@pytest.mark.asyncio
async def test_start_craft_not_enough_resources(async_session: AsyncSession, test_user):
    recipe = CraftRecipe(name="Test Fail", item_type="fail", grade=1, craft_time_sec=0)
    async_session.add(recipe)
    await async_session.flush()
    resource = CraftRecipeResource(recipe_id=recipe.id, resource_id=204, quantity=2, type="pvp")
    async_session.add(resource)
    await async_session.flush()
    stash = Stash(user_id=test_user.id, item_id=204, quantity=1)
    async_session.add(stash)
    await async_session.flush()
    service = CraftService(async_session)
    with pytest.raises(ValueError):
        await service.start_craft(test_user.id, recipe.id)

@pytest.mark.asyncio
async def test_can_craft_pvp_pve(async_session: AsyncSession, test_user):
    recipe = CraftRecipe(name="Test PvP/PvE", item_type="weapon", grade=3, craft_time_sec=0)
    async_session.add(recipe)
    await async_session.flush()
    res1 = CraftRecipeResource(recipe_id=recipe.id, resource_id=1, quantity=2, type="pvp")
    res2 = CraftRecipeResource(recipe_id=recipe.id, resource_id=101, quantity=1, type="pve")
    async_session.add_all([res1, res2])
    await async_session.flush()
    stash1 = Stash(user_id=test_user.id, item_id=1, quantity=2)
    stash2 = Stash(user_id=test_user.id, item_id=101, quantity=1)
    async_session.add_all([stash1, stash2])
    await async_session.flush()
    service = CraftService(async_session)
    can_craft = await service.can_craft(test_user.id, recipe)
    assert can_craft

@pytest.mark.asyncio
async def test_epic_legendary_limit(async_session: AsyncSession, test_user):
    today = datetime.utcnow()
    crafted = CraftedItem(user_id=test_user.id, item_type="artifact", grade=4, is_mutated=False, created_at=datetime(today.year, today.month, today.day))
    async_session.add(crafted)
    await async_session.flush()
    recipe = CraftRecipe(
        name="Epic",
        item_type="artifact",
        grade=4,
        craft_time_sec=0
    )
    async_session.add(recipe)
    await async_session.flush()
    service = CraftService(async_session)
    with pytest.raises(ValueError):
        await service.start_craft(test_user.id, recipe.id)

@pytest.mark.asyncio
async def test_disenchant_returns_resources(async_session: AsyncSession, test_user):
    crafted = CraftedItem(user_id=test_user.id, item_type="weapon", grade=3, is_mutated=False)
    async_session.add(crafted)
    recipe = CraftRecipe(
        item_type="weapon",
        grade=3,
        craft_time_sec=0
    )
    async_session.add(recipe)
    await async_session.flush()
    res1 = CraftRecipeResource(recipe_id=recipe.id, resource_id=1, quantity=4, type="pvp")
    res2 = CraftRecipeResource(recipe_id=recipe.id, resource_id=101, quantity=2, type="pve")
    async_session.add_all([res1, res2])
    await async_session.flush()
    service = CraftService(async_session)
    returned = await service.disenchant_item(test_user.id, crafted.id)
    for res in recipe.resources:
        assert returned[str(res.resource_id)] == int(res.quantity * 0.5)
    stash1 = await async_session.execute(Stash.__table__.select().where(Stash.user_id == test_user.id, Stash.item_id == 1))
    stash2 = await async_session.execute(Stash.__table__.select().where(Stash.user_id == test_user.id, Stash.item_id == 101))
    assert stash1.first() is not None
    assert stash2.first() is not None

@pytest.mark.asyncio
async def test_mutation_chance(async_session: AsyncSession, test_user, monkeypatch):
    # Примусово підміняємо random.random, щоб перевірити мутацію
    recipe = CraftRecipe(
        name="Mutate",
        item_type="artifact",
        grade=3,
        craft_time_sec=0
    )
    async_session.add(recipe)
    await async_session.flush()
    monkeypatch.setattr("random.random", lambda: 0.0)  # 0.0 < 0.005 => мутація
    service = CraftService(async_session)
    queue = await service.start_craft(test_user.id, recipe.id)
    crafted = await service.finish_craft(queue.id)
    assert crafted.is_mutated 

@pytest.mark.asyncio
async def test_craft_not_enough_pvp(async_session: AsyncSession, test_user):
    recipe = CraftRecipe(
        name="No PvP",
        item_type="weapon",
        grade=2,
        craft_time_sec=0
    )
    async_session.add(recipe)
    await async_session.flush()
    stash = Stash(user_id=test_user.id, item_id=1, quantity=2)
    async_session.add(stash)
    await async_session.flush()
    service = CraftService(async_session)
    can_craft = await service.can_craft(test_user.id, recipe)
    assert not can_craft
    with pytest.raises(ValueError):
        await service.start_craft(test_user.id, recipe.id)

@pytest.mark.asyncio
async def test_craft_not_enough_pve(async_session: AsyncSession, test_user):
    recipe = CraftRecipe(
        name="No PvE",
        item_type="artifact",
        grade=2,
        craft_time_sec=0
    )
    async_session.add(recipe)
    await async_session.flush()
    stash = Stash(user_id=test_user.id, item_id=101, quantity=1)
    async_session.add(stash)
    await async_session.flush()
    service = CraftService(async_session)
    can_craft = await service.can_craft(test_user.id, recipe)
    assert not can_craft
    with pytest.raises(ValueError):
        await service.start_craft(test_user.id, recipe.id)

@pytest.mark.asyncio
async def test_craft_timer(async_session: AsyncSession, test_user, monkeypatch):
    recipe = CraftRecipe(
        name="Timer",
        item_type="artifact",
        grade=2,
        craft_time_sec=100
    )
    async_session.add(recipe)
    await async_session.flush()
    service = CraftService(async_session)
    queue = await service.start_craft(test_user.id, recipe.id)
    assert (queue.ready_at - datetime.utcnow()).total_seconds() > 90
    with pytest.raises(ValueError):
        await service.finish_craft(queue.id)
    # Підміняємо ready_at щоб завершити
    queue.ready_at = datetime.utcnow() - timedelta(seconds=1)
    await async_session.flush()
    crafted = await service.finish_craft(queue.id)
    assert crafted.item_type == recipe.item_type

@pytest.mark.asyncio
async def test_disenchant_not_found(async_session: AsyncSession, test_user):
    with pytest.raises(ValueError):
        service = CraftService(async_session)
        await service.disenchant_item(test_user.id, 9999)

@pytest.mark.asyncio
async def test_disenchant_not_owner(async_session: AsyncSession, test_user):
    crafted = CraftedItem(user_id=999, item_type="artifact", grade=2, is_mutated=False)
    async_session.add(crafted)
    await async_session.flush()
    with pytest.raises(ValueError):
        service = CraftService(async_session)
        await service.disenchant_item(test_user.id, crafted.id)

@pytest.mark.asyncio
async def test_craft_zero_resources(async_session: AsyncSession, test_user):
    recipe = CraftRecipe(
        name="Zero",
        item_type="artifact",
        grade=2,
        craft_time_sec=0
    )
    async_session.add(recipe)
    await async_session.flush()
    service = CraftService(async_session)
    queue = await service.start_craft(test_user.id, recipe.id)
    crafted = await service.finish_craft(queue.id)
    assert crafted.item_type == recipe.item_type

@pytest.mark.asyncio
async def test_craft_invalid_recipe(async_session: AsyncSession, test_user):
    with pytest.raises(ValueError):
        service = CraftService(async_session)
        await service.start_craft(test_user.id, 9999)

@pytest.mark.asyncio
async def test_multiple_craft_queues(async_session: AsyncSession, test_user):
    recipe = CraftRecipe(
        name="Multi",
        item_type="artifact",
        grade=2,
        craft_time_sec=0
    )
    async_session.add(recipe)
    await async_session.flush()
    service = CraftService(async_session)
    q1 = await service.start_craft(test_user.id, recipe.id)
    q2 = await service.start_craft(test_user.id, recipe.id)
    assert q1.id != q2.id
    c1 = await service.finish_craft(q1.id)
    c2 = await service.finish_craft(q2.id)
    assert c1.item_type == c2.item_type

@pytest.mark.asyncio
async def test_ready_at_field(async_session: AsyncSession, test_user):
    recipe = CraftRecipe(
        name="ReadyAt",
        item_type="artifact",
        grade=2,
        craft_time_sec=123
    )
    async_session.add(recipe)
    await async_session.flush()
    service = CraftService(async_session)
    queue = await service.start_craft(test_user.id, recipe.id)
    assert isinstance(queue.ready_at, datetime)

@pytest.mark.asyncio
async def test_disenchant_removes_item(async_session: AsyncSession, test_user):
    crafted = CraftedItem(user_id=test_user.id, item_type="artifact", grade=2, is_mutated=False)
    async_session.add(crafted)
    recipe = CraftRecipe(item_type="artifact", grade=2, craft_time_sec=0)
    async_session.add(recipe)
    await async_session.flush()
    service = CraftService(async_session)
    await service.disenchant_item(test_user.id, crafted.id)
    # Перевіряємо, що предмет видалено
    c = await async_session.get(CraftedItem, crafted.id)
    assert c is None 