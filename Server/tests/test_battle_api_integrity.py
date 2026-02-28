import asyncio
from decimal import Decimal
from uuid import uuid4

import pytest
from httpx import AsyncClient
from sqlalchemy import delete, select
from sqlalchemy.exc import IntegrityError

from app.database.models.battle import BattleBet, BattleQueueEntry
from app.database.models.hero import Hero
from app.database.models.user import User
from app.utils.jwt import create_access_token


def _auth_headers(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


async def _create_hero(async_session, owner_id: int, name: str) -> Hero:
    hero = Hero(
        name=name,
        generation=1,
        nickname=name,
        strength=12,
        agility=8,
        intelligence=5,
        endurance=10,
        speed=9,
        health=50,
        defense=7,
        luck=3,
        field_of_view=6,
        level=1,
        experience=0,
        locale="en",
        owner_id=owner_id,
    )
    async_session.add(hero)
    await async_session.commit()
    await async_session.refresh(hero)
    return hero


async def _get_fresh_user(async_session, user_id: int) -> User:
    async_session.expire_all()
    result = await async_session.execute(select(User).where(User.id == user_id))
    return result.scalars().first()


async def _count_bets(async_session, bettor_id: int, hero_id: int) -> int:
    async_session.expire_all()
    result = await async_session.execute(
        select(BattleBet).where(BattleBet.bettor_id == bettor_id, BattleBet.hero_id == hero_id)
    )
    return len(result.scalars().all())


@pytest.fixture
async def clean_battle_state(async_session):
    await async_session.execute(delete(BattleBet))
    await async_session.execute(delete(BattleQueueEntry))
    await async_session.commit()


@pytest.fixture
async def second_user_and_token(async_session):
    suffix = uuid4().hex[:8]
    user = User(
        username=f"battle_other_{suffix}",
        email=f"battle_other_{suffix}@example.com",
        balance=Decimal("1000.00"),
        reserved=Decimal("0.00"),
    )
    async_session.add(user)
    await async_session.commit()
    await async_session.refresh(user)
    token = create_access_token({"sub": str(user.id), "role": user.role})
    return user, token


@pytest.mark.asyncio
async def test_queue_submit_success(test_client: AsyncClient, test_user, test_user_token, async_session, clean_battle_state):
    hero = await _create_hero(async_session, test_user.id, "QueueHeroA")

    response = await test_client.post(
        "/battle/queue/submit",
        json={"hero_id": hero.id},
        headers=_auth_headers(test_user_token),
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["hero_id"] == hero.id


@pytest.mark.asyncio
async def test_duplicate_submit_prevention(test_client: AsyncClient, test_user, test_user_token, async_session, clean_battle_state):
    hero = await _create_hero(async_session, test_user.id, "QueueHeroDup")

    first = await test_client.post(
        "/battle/queue/submit",
        json={"hero_id": hero.id},
        headers=_auth_headers(test_user_token),
    )
    second = await test_client.post(
        "/battle/queue/submit",
        json={"hero_id": hero.id},
        headers=_auth_headers(test_user_token),
    )

    assert first.status_code == 200
    assert second.status_code == 409


@pytest.mark.asyncio
async def test_concurrent_submit_same_hero_single_winner(test_client: AsyncClient, test_user, test_user_token, async_session, clean_battle_state):
    hero = await _create_hero(async_session, test_user.id, "QueueHeroConcurrent")

    async def submit_once():
        return await test_client.post(
            "/battle/queue/submit",
            json={"hero_id": hero.id},
            headers=_auth_headers(test_user_token),
        )

    resp1, resp2 = await asyncio.gather(submit_once(), submit_once())

    statuses = sorted([resp1.status_code, resp2.status_code])
    assert statuses == [200, 409]


@pytest.mark.asyncio
async def test_bet_placement_atomicity_updates_reserved_once(
    test_client: AsyncClient,
    test_user,
    test_user_token,
    second_user_and_token,
    async_session,
    clean_battle_state,
):
    other_user, other_token = second_user_and_token
    test_user_id = test_user.id
    hero = await _create_hero(async_session, other_user.id, "BetTargetAtomic")
    hero_id = hero.id

    await test_client.post(
        "/battle/queue/submit",
        json={"hero_id": hero.id},
        headers=_auth_headers(other_token),
    )

    response = await test_client.post(
        "/battle/bet",
        json={"hero_id": hero.id, "amount": "123.45"},
        headers=_auth_headers(test_user_token),
    )

    assert response.status_code == 200

    fresh_user = await _get_fresh_user(async_session, test_user_id)
    assert Decimal(fresh_user.reserved) == Decimal("123.45")

    bets = await async_session.execute(
        select(BattleBet).where(BattleBet.bettor_id == test_user_id, BattleBet.hero_id == hero_id)
    )
    assert len(bets.scalars().all()) == 1


@pytest.mark.asyncio
async def test_bet_exceeding_balance_rejected(
    test_client: AsyncClient,
    test_user,
    test_user_token,
    second_user_and_token,
    async_session,
    clean_battle_state,
):
    other_user, other_token = second_user_and_token
    test_user_id = test_user.id
    hero = await _create_hero(async_session, other_user.id, "BetTargetLowBalance")

    test_user.balance = Decimal("50.00")
    test_user.reserved = Decimal("0.00")
    await async_session.commit()

    await test_client.post(
        "/battle/queue/submit",
        json={"hero_id": hero.id},
        headers=_auth_headers(other_token),
    )

    response = await test_client.post(
        "/battle/bet",
        json={"hero_id": hero.id, "amount": "60.00"},
        headers=_auth_headers(test_user_token),
    )

    assert response.status_code == 400
    assert response.json()["detail"] == "Insufficient funds"

    fresh_user = await _get_fresh_user(async_session, test_user_id)
    assert Decimal(fresh_user.reserved) == Decimal("0.00")


@pytest.mark.asyncio
async def test_queue_polling_consistency(
    test_client: AsyncClient,
    test_user,
    test_user_token,
    second_user_and_token,
    async_session,
    clean_battle_state,
):
    other_user, other_token = second_user_and_token
    hero1 = await _create_hero(async_session, test_user.id, "QueuePollA")
    hero2 = await _create_hero(async_session, other_user.id, "QueuePollB")

    await test_client.post(
        "/battle/queue/submit",
        json={"hero_id": hero1.id},
        headers=_auth_headers(test_user_token),
    )
    await test_client.post(
        "/battle/queue/submit",
        json={"hero_id": hero2.id},
        headers=_auth_headers(other_token),
    )

    first = await test_client.get("/battle/queue", headers=_auth_headers(test_user_token))
    second = await test_client.get("/battle/queue", headers=_auth_headers(test_user_token))

    assert first.status_code == 200
    assert second.status_code == 200
    assert first.json() == second.json()
    assert [entry["hero_id"] for entry in first.json()] == [hero1.id, hero2.id]


@pytest.mark.asyncio
async def test_concurrent_double_bet_prevented(
    test_client: AsyncClient,
    test_user,
    test_user_token,
    second_user_and_token,
    async_session,
    clean_battle_state,
):
    other_user, other_token = second_user_and_token
    hero = await _create_hero(async_session, other_user.id, "BetTargetConcurrent")

    await test_client.post(
        "/battle/queue/submit",
        json={"hero_id": hero.id},
        headers=_auth_headers(other_token),
    )

    async def place_bet_once():
        return await test_client.post(
            "/battle/bet",
            json={"hero_id": hero.id, "amount": "10.00"},
            headers=_auth_headers(test_user_token),
        )

    resp1, resp2 = await asyncio.gather(place_bet_once(), place_bet_once())

    statuses = sorted([resp1.status_code, resp2.status_code])
    assert statuses == [200, 409]


@pytest.mark.asyncio
async def test_bet_amount_db_check_constraint(async_session, test_user, clean_battle_state):
    hero = await _create_hero(async_session, test_user.id, "BetConstraintHero")
    invalid_bet = BattleBet(bettor_id=test_user.id, hero_id=hero.id, amount=Decimal("-1.00"))
    async_session.add(invalid_bet)

    with pytest.raises(IntegrityError):
        await async_session.commit()

    await async_session.rollback()
