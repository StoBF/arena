from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Any, Dict, List
from datetime import datetime
from pydantic import BaseModel
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
# ---------- simple queue & betting prototype ----------
queue: List[Dict[str, Any]] = []  # {hero_id, player_id, timestamp}
bets: List[Dict[str, Any]] = []   # {player_id, hero_id, amount}
# placeholder stats
_hero_stats = {
    1: {"hero_id":1, "attack":10, "defense":8, "health":50},
    2: {"hero_id":2, "attack":7, "defense":12, "health":45},
}

class SubmitIn(BaseModel):
    hero_id: int

class BetIn(BaseModel):
    hero_id: int
    amount: int

@router.post("/queue/submit")
async def submit_queue(data: SubmitIn, current_user=Depends(get_current_user_info)):
    entry = {"hero_id": data.hero_id, "player_id": current_user["user_id"], "timestamp": datetime.utcnow()}
    queue.append(entry)
    return {"status":"ok"}

@router.get("/queue")
async def get_queue():
    return queue

@router.get("/hero/{hero_id}")
async def get_hero_stats(hero_id: int):
    stats = _hero_stats.get(hero_id)
    if not stats:
        raise HTTPException(404, "Hero not found")
    return stats

@router.post("/bet")
async def post_bet(data: BetIn, current_user=Depends(get_current_user_info)):
    bets.append({"player_id": current_user["user_id"], "hero_id": data.hero_id, "amount": data.amount})
    return {"status":"ok"}

@router.get("/predict")
async def predict():
    if len(queue) < 2:
        raise HTTPException(400, "not enough heroes")
    h1 = _hero_stats.get(queue[0]["hero_id"])
    h2 = _hero_stats.get(queue[1]["hero_id"])
    score1 = h1["attack"] + h1["defense"] + h1["health"]
    score2 = h2["attack"] + h2["defense"] + h2["health"]
    winner = queue[0]["hero_id"] if score1 >= score2 else queue[1]["hero_id"]
    chance = score1/float(score1+score2)
    return {"winner_id": winner, "chance": chance}
