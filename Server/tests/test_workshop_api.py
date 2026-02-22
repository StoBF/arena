import pytest
from httpx import AsyncClient
from app.main import app
from app.database.models.perk import Perk
from app.database.models.hero import Hero, HeroPerk

@pytest.mark.asyncio
async def test_workshop_available(test_client: AsyncClient, test_user_token):
    response = await test_client.get("/workshop/available", headers={"Authorization": f"Bearer {test_user_token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)

@pytest.mark.asyncio
async def test_workshop_craft_and_finish(test_client: AsyncClient, test_user_token):
    # Старт крафту
    response = await test_client.post("/workshop/craft/1", headers={"Authorization": f"Bearer {test_user_token}"})
    assert response.status_code == 200
    queue_id = response.json()["id"]
    # Завершення крафту (штучно підмінити ready_at у БД, якщо треба)
    response = await test_client.post(f"/workshop/finish/{queue_id}", headers={"Authorization": f"Bearer {test_user_token}"})
    assert response.status_code == 200
    assert "item_type" in response.json()

@pytest.mark.asyncio
async def test_workshop_queue(test_client: AsyncClient, test_user_token):
    response = await test_client.get("/workshop/queue", headers={"Authorization": f"Bearer {test_user_token}"})
    assert response.status_code == 200
    assert isinstance(response.json(), list)

@pytest.mark.asyncio
async def test_workshop_disenchant(test_client: AsyncClient, test_user_token):
    # Створити предмет через крафт
    response = await test_client.post("/workshop/craft/1", headers={"Authorization": f"Bearer {test_user_token}"})
    queue_id = response.json()["id"]
    await test_client.post(f"/workshop/finish/{queue_id}", headers={"Authorization": f"Bearer {test_user_token}"})
    # Знайти CraftedItem (можливо через окремий ендпоінт або з БД)
    # Тут припускаємо, що id=1 (або отримати з відповіді)
    response = await test_client.post("/workshop/disenchant/1", headers={"Authorization": f"Bearer {test_user_token}"})
    assert response.status_code == 200
    assert "returned_resources" in response.json()

@pytest.mark.asyncio
async def test_workshop_craft_not_enough_resources(test_client: AsyncClient, test_user_token):
    response = await test_client.post("/workshop/craft/999", headers={"Authorization": f"Bearer {test_user_token}"})
    assert response.status_code == 400

@pytest.mark.asyncio
async def test_workshop_disenchant_not_found(test_client: AsyncClient, test_user_token):
    response = await test_client.post("/workshop/disenchant/9999", headers={"Authorization": f"Bearer {test_user_token}"})
    assert response.status_code == 400

@pytest.mark.asyncio
async def test_workshop_disenchant_not_owner(test_client: AsyncClient, test_user_token, other_user_crafted_item_id):
    response = await test_client.post(f"/workshop/disenchant/{other_user_crafted_item_id}", headers={"Authorization": f"Bearer {test_user_token}"})
    assert response.status_code == 400

@pytest.mark.asyncio
async def test_upgrade_perk_api(async_session):
    # Створюємо героя
    hero = Hero(name="APIHero", generation=1, nickname="API", strength=10, agility=10, intelligence=10, endurance=10, speed=10, health=100, defense=5, luck=3, field_of_view=10, level=1, experience=0, locale="en", owner_id=1)
    async_session.add(hero)
    await async_session.flush()
    # Створюємо перк
    perk = Perk(name="APIPerk", description="Test", max_level=100, modifiers={"strength": 1})
    async_session.add(perk)
    await async_session.flush()
    # Додаємо перк герою
    hero_perk = HeroPerk(hero_id=hero.id, perk_id=perk.id, perk_level=10)
    async_session.add(hero_perk)
    await async_session.commit()
    # Тестовий токен/юзер (залежить від вашої авторизації, тут user_id=1)
    async with AsyncClient(app=app, base_url="http://test") as ac:
        resp = await ac.post(f"/heroes/{hero.id}/perks/upgrade", json={"perk_id": perk.id})
        assert resp.status_code == 200
        data = resp.json()
        assert data["perk_id"] == perk.id
        assert data["perk_level"] == 11 