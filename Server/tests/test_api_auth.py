import pytest
from httpx import AsyncClient
from app.main import app

@pytest.mark.asyncio
async def test_auth_flow():
    async with AsyncClient(app=app, base_url="http://test") as ac:
        # Реєстрація
        resp = await ac.post("/auth/register", json={
            "email": "apiuser@example.com",
            "username": "apiuser",
            "password": "apipass123"
        })
        assert resp.status_code == 200
        # Логін
        resp = await ac.post("/auth/login", json={
            "login": "apiuser@example.com",
            "password": "apipass123"
        })
        assert resp.status_code == 200
        data = resp.json()
        assert "access_token" in data and "refresh_token" in data
        # Оновлення access токена
        resp2 = await ac.post("/auth/refresh", json={"refresh_token": data["refresh_token"]})
        assert resp2.status_code == 200
        assert "access_token" in resp2.json() 