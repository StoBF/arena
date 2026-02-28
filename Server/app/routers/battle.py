from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, condecimal
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.database.models.battle import BattleBet, BattleQueueEntry
from app.database.models.currency_transaction import CurrencyTransaction
from app.database.models.hero import Hero
from app.database.models.user import User
from app.services.combat import CombatService
from app.database.session import get_session
from app.auth import get_current_user_info
from app.services.hero import HeroService

router = APIRouter(prefix="/battle", tags=["Battle"])

@router.post("/duel", summary="Start a duel between two heroes")
async def duel(
    hero_id: int,
    enemy_id: int,
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    hero = await HeroService(db).get_hero(hero_id)
    enemy = await HeroService(db).get_hero(enemy_id)
    if not hero or hero.owner_id != current_user["user_id"]:
        raise HTTPException(404, "Your hero not found")
    if hero.is_dead:
        raise HTTPException(400, f"Your hero is dead until {hero.dead_until}")
    if hero.is_training:
        raise HTTPException(400, "Your hero is training")
    if not enemy:
        raise HTTPException(404, "Enemy hero not found")
    if enemy.is_dead:
        raise HTTPException(400, f"Enemy hero is dead until {enemy.dead_until}")
    result = await CombatService(db).simulate_duel(hero, enemy)
    return {
        "winner": result.winner,
        "log": result.log,
        "rewards": result.rewards,
        "team_a_remaining": result.team_a_remaining,
        "team_b_remaining": result.team_b_remaining
    }

@router.post("/team", summary="Start a team battle")
async def team_battle(
    hero_ids: List[int],
    enemy_ids: List[int],
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    heroes = [await HeroService(db).get_hero(hid) for hid in hero_ids]
    enemies = [await HeroService(db).get_hero(eid) for eid in enemy_ids]
    for h in heroes:
        if not h or h.owner_id != current_user["user_id"]:
            raise HTTPException(404, "Your hero not found")
        if h.is_dead:
            raise HTTPException(400, f"Hero {h.name} is dead until {h.dead_until}")
        if h.is_training:
            raise HTTPException(400, f"Hero {h.name} is training")
    for e in enemies:
        if not e:
            raise HTTPException(404, "Enemy hero not found")
        if e.is_dead:
            raise HTTPException(400, f"Enemy hero {e.name} is dead until {e.dead_until}")
    result = await CombatService(db).simulate_team_battle(heroes, enemies)
    return {
        "winner": result.winner,
        "log": result.log,
        "rewards": result.rewards,
        "team_a_remaining": result.team_a_remaining,
        "team_b_remaining": result.team_b_remaining
    }

@router.post("/raid", summary="Start a raid battle")
async def raid(
    hero_ids: List[int],
    boss_id: int,
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    heroes = [await HeroService(db).get_hero(hid) for hid in hero_ids]
    boss = await HeroService(db).get_hero(boss_id)
    for h in heroes:
        if not h or h.owner_id != current_user["user_id"]:
            raise HTTPException(404, "Your hero not found")
        if h.is_dead:
            raise HTTPException(400, f"Hero {h.name} is dead until {h.dead_until}")
        if h.is_training:
            raise HTTPException(400, f"Hero {h.name} is training")
    if not boss:
        raise HTTPException(404, "Boss not found")
    if boss.is_dead:
        raise HTTPException(400, f"Boss is dead until {boss.dead_until}")
    result = await CombatService(db).simulate_raid(heroes, boss)
    return {
        "winner": result.winner,
        "log": result.log,
        "rewards": result.rewards,
        "team_a_remaining": result.team_a_remaining,
        "team_b_remaining": result.team_b_remaining
    } 
class SubmitIn(BaseModel):
    hero_id: int

class BetIn(BaseModel):
    hero_id: int
    amount: condecimal(gt=0, max_digits=12, decimal_places=2)

@router.post("/queue/submit")
async def submit_queue(
    data: SubmitIn,
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    user_id = current_user["user_id"]

    tx = db.begin_nested() if db.in_transaction() else db.begin()
    try:
        async with tx:
            hero_result = await db.execute(
                select(Hero).where(Hero.id == data.hero_id, Hero.owner_id == user_id)
            )
            hero = hero_result.scalars().first()
            if not hero:
                raise HTTPException(status_code=404, detail="Hero not found")
            if hero.is_dead:
                raise HTTPException(status_code=400, detail="Hero is dead")
            if hero.is_training:
                raise HTTPException(status_code=400, detail="Hero is training")

            queue_entry = BattleQueueEntry(hero_id=data.hero_id, player_id=user_id)
            db.add(queue_entry)
            await db.flush()

            payload = {
                "status": "ok",
                "queue_id": queue_entry.id,
                "hero_id": queue_entry.hero_id,
                "player_id": queue_entry.player_id,
            }
    except IntegrityError:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Hero already queued or player already has queued hero"
        )
    return payload

@router.get("/queue")
async def get_queue(db: AsyncSession = Depends(get_session)):
    queue_result = await db.execute(
        select(BattleQueueEntry).order_by(BattleQueueEntry.created_at.asc(), BattleQueueEntry.id.asc())
    )
    queue_entries = queue_result.scalars().all()
    return [
        {
            "id": entry.id,
            "hero_id": entry.hero_id,
            "player_id": entry.player_id,
            "created_at": entry.created_at,
        }
        for entry in queue_entries
    ]

@router.get("/hero/{hero_id}")
async def get_hero_stats(hero_id: int, db: AsyncSession = Depends(get_session)):
    hero_result = await db.execute(select(Hero).where(Hero.id == hero_id))
    hero = hero_result.scalars().first()
    if not hero:
        raise HTTPException(404, "Hero not found")
    return {
        "hero_id": hero.id,
        "attack": hero.strength,
        "defense": hero.defense,
        "health": hero.health,
    }

@router.post("/bet")
async def post_bet(
    data: BetIn,
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    bettor_id = current_user["user_id"]
    amount = Decimal(data.amount)

    tx = db.begin_nested() if db.in_transaction() else db.begin()
    try:
        async with tx:
            queued_result = await db.execute(
                select(BattleQueueEntry).where(BattleQueueEntry.hero_id == data.hero_id)
            )
            queued_hero = queued_result.scalars().first()
            if not queued_hero:
                raise HTTPException(status_code=400, detail="Hero is not in battle queue")

            lock_user_result = await db.execute(
                select(User).where(User.id == bettor_id).with_for_update()
            )
            if not lock_user_result.scalars().first():
                raise HTTPException(status_code=404, detail="User not found")

            reserve_update = await db.execute(
                update(User)
                .where(
                    User.id == bettor_id,
                    (User.balance - User.reserved) >= amount,
                )
                .values(reserved=User.reserved + amount)
            )
            if reserve_update.rowcount != 1:
                raise HTTPException(status_code=400, detail="Insufficient funds")

            db.add(
                BattleBet(
                    bettor_id=bettor_id,
                    hero_id=data.hero_id,
                    amount=amount,
                )
            )
            db.add(
                CurrencyTransaction(
                    user_id=bettor_id,
                    amount=amount,
                    type="battle_bet_reserved",
                    reference_id=data.hero_id,
                )
            )
    except IntegrityError:
        await db.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Bet already placed")

    return {
        "status": "ok",
        "hero_id": data.hero_id,
        "amount": str(amount),
    }

@router.get("/predict")
async def predict(db: AsyncSession = Depends(get_session)):
    queue_result = await db.execute(
        select(BattleQueueEntry).order_by(BattleQueueEntry.created_at.asc(), BattleQueueEntry.id.asc()).limit(2)
    )
    queue = queue_result.scalars().all()
    if len(queue) < 2:
        raise HTTPException(400, "not enough heroes")
    heroes_result = await db.execute(select(Hero).where(Hero.id.in_([queue[0].hero_id, queue[1].hero_id])))
    heroes = {hero.id: hero for hero in heroes_result.scalars().all()}
    h1 = heroes.get(queue[0].hero_id)
    h2 = heroes.get(queue[1].hero_id)
    if not h1 or not h2:
        raise HTTPException(400, "hero stats unavailable")
    score1 = h1.strength + h1.defense + h1.health
    score2 = h2.strength + h2.defense + h2.health
    winner = queue[0].hero_id if score1 >= score2 else queue[1].hero_id
    chance = score1/float(score1+score2)
    return {"winner_id": winner, "chance": chance}
