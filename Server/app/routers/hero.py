from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
from app.schemas.hero import HeroCreate, HeroOut, HeroRead, HeroGenerateRequest, PerkUpgradeRequest
from app.schemas.pagination import HeroesPaginatedResponse
from app.services.hero import HeroService
from app.database.session import get_session
from app.auth import get_current_user, get_current_user_info
from app.core.redis_cache import redis_cache

router = APIRouter(prefix="/heroes", tags=["Heroes"])

@router.get(
    "/",
    response_model=HeroesPaginatedResponse,
    summary="Get all heroes for the current user",
    description="Returns a paginated list of all heroes belonging to the authenticated user. Uses Redis cache for performance."
)
async def read_heroes(
    limit: int = Query(10, ge=1, le=100, description="Items per page (max 100)"),
    offset: int = Query(0, ge=0, description="Items to skip"),
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info)
):
    cache_key = f"heroes:{user['user_id']}:{limit}:{offset}"
    cached = await redis_cache.get(cache_key)
    if cached is not None:
        return cached
    
    result = await HeroService(db).list_heroes(user['user_id'], limit=limit, offset=offset)
    
    response = {
        "items": result["items"],
        "total": result["total"],
        "limit": result["limit"],
        "offset": result["offset"]
    }
    await redis_cache.set(cache_key, response, expire=60)
    return response

@router.get(
    "/{hero_id}",
    response_model=HeroRead,
    summary="Get a specific hero by ID",
    description="Returns detailed information about a specific hero owned by the authenticated user."
)
async def read_hero(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info)
):
    hero = await HeroService(db).get_hero(hero_id)
    if not hero or hero.owner_id != user['user_id']:
        raise HTTPException(404, "Hero not found")
    return hero

@router.post(
    "/generate",
    response_model=HeroRead,
    summary="Generate a new hero",
    description="Generates a new hero for the authenticated user based on the provided generation parameters."
)
async def generate_hero(
    req: HeroGenerateRequest,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info)
):
    hero = await HeroService(db).generate_and_store(user['user_id'], req)
    return hero

@router.delete(
    "/{hero_id}",
    response_model=HeroRead,
    summary="Delete a hero",
    description="Marks a hero as deleted for the authenticated user."
)
async def delete_hero(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info)
):
    hero = await HeroService(db).delete_hero(hero_id, user['user_id'])
    return hero

@router.post(
    "/{hero_id}/restore",
    response_model=HeroRead,
    summary="Restore a deleted hero",
    description="Restores a previously deleted hero for the authenticated user."
)
async def restore_hero(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info)
):
    hero = await HeroService(db).restore_hero(hero_id, user['user_id'])
    return hero

@router.post(
    "/{hero_id}/train",
    response_model=HeroRead,
    summary="Start hero training",
    description="Starts training for the specified hero. Only the owner can start training."
)
async def start_training(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
    duration_minutes: int = 60
):
    hero = await HeroService(db).get_hero(hero_id)
    if not hero or hero.owner_id != user['user_id']:
        raise HTTPException(404, "Hero not found")
    hero = await HeroService(db).start_training(hero_id, duration_minutes)
    return hero

@router.post(
    "/{hero_id}/complete_training",
    response_model=HeroRead,
    summary="Complete hero training",
    description="Completes training for the specified hero if the training time has finished. Only the owner can complete training."
)
async def complete_training(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
    xp_reward: int = 50
):
    hero = await HeroService(db).get_hero(hero_id)
    if not hero or hero.owner_id != user['user_id']:
        raise HTTPException(404, "Hero not found")
    hero = await HeroService(db).complete_training(hero_id, xp_reward)
    return hero

@router.post(
    "/{hero_id}/perks/upgrade",
    response_model=dict,  # Можна створити PerkOut, але для простоти dict
    summary="Upgrade a hero's perk",
    description="Upgrades the specified perk for the hero by +1 level (max 100). Only the owner can upgrade."
)
async def upgrade_perk(
    hero_id: int,
    req: PerkUpgradeRequest,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info)
):
    if not isinstance(req.perk_id, int):
        raise HTTPException(status_code=400, detail="perk_id must be an integer")
    result = await HeroService(db).upgrade_perk(hero_id, req.perk_id, user['user_id'])
    return {"perk_id": req.perk_id, "perk_level": result.perk_level}
