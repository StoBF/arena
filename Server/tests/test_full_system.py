import pytest
from httpx import AsyncClient
from sqlalchemy.future import select
from decimal import Decimal

from app.main import app
from app.database.models.craft import CraftRecipe, CraftRecipeResource, CraftedItem
from app.database.models.models import Stash, Item, Equipment
from app.services.hero import HeroService
from app.services.equipment import EquipmentService

# server fixtures (test_client, test_user_token, async_session) are defined in conftest.py

@pytest.mark.asyncio
async def test_jwt_auth_endpoints(test_client: AsyncClient):
    # register + login already tested in other file; here we confirm invalid token fails
    resp = await test_client.get("/heroes")
    assert resp.status_code == 401

@pytest.mark.asyncio
async def test_hero_creation_api(test_client: AsyncClient, test_user_token):
    # create hero through endpoint
    resp = await test_client.post(
        "/heroes",
        headers={"Authorization": f"Bearer {test_user_token}"},
        json={"name": "IntegrationHero"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["name"] == "IntegrationHero"
    assert "id" in data

@pytest.mark.asyncio
async def test_crafting_api_resource_deduction_and_mutation(async_session, test_client: AsyncClient, test_user_token, test_user):
    # create recipe and resources
    recipe = CraftRecipe(
        name="TestRecipe",
        item_type="equipment",
        grade=1,
        craft_time_sec=0,
        result_item_id=None,
    )
    async_session.add(recipe)
    await async_session.flush()
    comp = CraftRecipeResource(recipe_id=recipe.id, resource_id=1111, quantity=2, type="pvp")
    async_session.add(comp)
    # give user stash resources
    stash = Stash(user_id=test_user.id, item_id=1111, quantity=5)
    async_session.add(stash)
    await async_session.commit()

    # start craft
    resp = await test_client.post(f"/workshop/craft/{recipe.id}", headers={"Authorization": f"Bearer {test_user_token}"})
    assert resp.status_code == 200
    queue = resp.json()
    # stash was deducted
    stash = (await async_session.execute(
        select(Stash).where(Stash.user_id == test_user.id, Stash.item_id == 1111)
    )).scalars().first()
    assert stash.quantity == 3
    # finish craft
    resp = await test_client.post(f"/workshop/finish/{queue['id']}", headers={"Authorization": f"Bearer {test_user_token}"})
    assert resp.status_code == 200
    item = resp.json()
    assert "is_mutated" in item
    assert isinstance(item["is_mutated"], bool)

@pytest.mark.asyncio
async def test_equipment_api_changes_hero_stats(async_session, test_client: AsyncClient, test_user_token, test_user):
    # create hero via service (bypass API to know id and stats)
    hero = await HeroService(async_session).create_hero("EquipHero", test_user.id)
    await async_session.commit()
    # create item with bonuses and put to stash
    item = Item(name="Helmet of Strength", description="", slot_type="helmet", bonus_strength=4, bonus_agility=1)
    async_session.add(item)
    await async_session.commit()
    stash = Stash(user_id=test_user.id, item_id=item.id, quantity=1)
    async_session.add(stash)
    await async_session.commit()

    # equip via API
    resp = await test_client.post(
        "/equipment/",
        headers={"Authorization": f"Bearer {test_user_token}"},
        json={"hero_id": hero.id, "item_id": item.id, "slot": "helmet"},
    )
    assert resp.status_code == 200
    eqdata = resp.json()
    assert eqdata["hero_id"] == hero.id
    assert eqdata["item_id"] == item.id

    # compute stats using service (endpoint does not return bonus)
    stats = await HeroService(async_session).get_total_stats(hero.id)
    assert stats["strength"] >= hero.strength + 4
    assert stats["agility"] >= hero.agility + 1

@pytest.mark.asyncio
async def test_warehouse_api_and_insufficient_resources(test_client: AsyncClient, test_user_token, async_session, test_user):
    # add stash entries
    st1 = Stash(user_id=test_user.id, item_id=2222, quantity=3)
    async_session.add(st1)
    await async_session.commit()

    resp = await test_client.get("/inventory/", headers={"Authorization": f"Bearer {test_user_token}"})
    assert resp.status_code == 200
    items = resp.json()
    assert any(i["item_id"] == 2222 and i["quantity"] == 3 for i in items)

    # try to craft with insufficient resources using non-existent recipe
    resp = await test_client.post("/workshop/craft/99999", headers={"Authorization": f"Bearer {test_user_token}"})
    assert resp.status_code == 400

@pytest.mark.asyncio
async def test_integration_client_like_flow(async_session, test_client: AsyncClient, test_user_token, test_user):
    # combination of craft + equip to mimic client/server interaction
    # create recipe and stash
    recipe = CraftRecipe(name="FlowRecipe", item_type="equipment", grade=1, craft_time_sec=0, result_item_id=None)
    async_session.add(recipe)
    await async_session.flush()
    comp = CraftRecipeResource(recipe_id=recipe.id, resource_id=3333, quantity=1, type="pvp")
    async_session.add(comp)
    stash = Stash(user_id=test_user.id, item_id=3333, quantity=1)
    async_session.add(stash)
    await async_session.commit()

    # craft
    resp = await test_client.post(f"/workshop/craft/{recipe.id}", headers={"Authorization": f"Bearer {test_user_token}"})
    queue_id = resp.json()["id"]
    resp = await test_client.post(f"/workshop/finish/{queue_id}", headers={"Authorization": f"Bearer {test_user_token}"})
    assert resp.status_code == 200
    crafted = resp.json()

    # pretend crafted item is an equipment and add to stash manually
    new_item = Item(name="FlowGear", description="", slot_type="helmet")
    async_session.add(new_item)
    await async_session.flush()
    async_session.add(Stash(user_id=test_user.id, item_id=new_item.id, quantity=1))
    await async_session.commit()

    # equip it via API and ensure hero stats update
    hero = await HeroService(async_session).create_hero("FlowHero", test_user.id)
    await async_session.commit()
    resp = await test_client.post(
        "/equipment/",
        headers={"Authorization": f"Bearer {test_user_token}"},
        json={"hero_id": hero.id, "item_id": new_item.id, "slot": "helmet"},
    )
    assert resp.status_code == 200
    stats = await HeroService(async_session).get_total_stats(hero.id)
    # since new_item has no bonuses, stats should be unchanged
    assert stats["strength"] == hero.strength
```