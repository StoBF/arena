import pytest
from uuid import uuid4


@pytest.mark.asyncio
async def test_server_status_contract(test_client):
    response = await test_client.get("/server/status")
    assert response.status_code == 200

    payload = response.json()
    assert payload.get("status") == "online"
    assert isinstance(payload.get("online_players"), int)
    assert payload.get("online_players") >= 0


@pytest.mark.asyncio
async def test_server_status_online_players_changes_on_login_logout(test_client):
    before_resp = await test_client.get("/server/status")
    assert before_resp.status_code == 200
    before_count = int(before_resp.json().get("online_players", 0))

    suffix = uuid4().hex[:8]
    email = f"status_{suffix}@example.com"
    username = f"status_user_{suffix}"
    password = "statuspass123"

    register_resp = await test_client.post(
        "/auth/register",
        json={"email": email, "username": username, "password": password},
    )
    assert register_resp.status_code == 200

    login_resp = await test_client.post(
        "/auth/login",
        json={"login": email, "password": password},
    )
    assert login_resp.status_code == 200
    access_token = login_resp.json().get("access_token", "")
    assert access_token

    after_login_resp = await test_client.get("/server/status")
    assert after_login_resp.status_code == 200
    after_login_count = int(after_login_resp.json().get("online_players", 0))
    assert after_login_count == before_count + 1

    logout_resp = await test_client.post(
        "/auth/logout",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    assert logout_resp.status_code == 200

    after_logout_resp = await test_client.get("/server/status")
    assert after_logout_resp.status_code == 200
    after_logout_count = int(after_logout_resp.json().get("online_players", 0))
    assert after_logout_count == before_count
