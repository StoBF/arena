from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
from app.services.combat import CombatService
from app.database.models.hero import Hero
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