from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
from app.schemas.hero import (
    HeroCreate, HeroRead, HeroGenerateRequest, PerkUpgradeRequest,
    HeroBodyResponse, BodyPartOut,
    TrainingStartRequest, TrainingQueueOut, TrainingQueueResponse,
    ResurrectRequest, ResurrectionEventOut, HeroStatusResponse,
)
from app.schemas.pagination import HeroesPaginatedResponse
from app.services.hero import HeroService
from app.services.training import TrainingService
from app.services.resurrection import ResurrectionService
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
    hero = await HeroService(db).get_hero_with_perks(hero_id)
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
    return await HeroService(db).get_hero_with_perks(hero.id)

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

@router.get(
    "/{hero_id}/body",
    response_model=HeroBodyResponse,
    summary="Get hero body parts",
    description="Returns the current state of all body parts for the specified hero."
)
async def get_hero_body(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info)
):
    hero = await HeroService(db).get_hero(hero_id)
    if not hero or hero.owner_id != user['user_id']:
        raise HTTPException(404, "Hero not found")
    parts = [
        BodyPartOut.model_validate(bp, from_attributes=True)
        for bp in (hero.body_parts or [])
    ]
    return HeroBodyResponse(hero_id=hero.id, parts=parts)

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


# ─── Training Queue endpoints ────────────────────────────────────────────

@router.post(
    "/{hero_id}/training/start",
    response_model=TrainingQueueOut,
    summary="Start queued training",
    description="Enqueues a new training entry for the hero. Supports attribute, discipline, and ability training types."
)
async def training_start(
    hero_id: int,
    req: TrainingStartRequest,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    return await TrainingService(db).start_training(hero_id, user['user_id'], req)


@router.post(
    "/{hero_id}/training/cancel",
    response_model=TrainingQueueOut,
    summary="Cancel a training entry",
    description="Cancels an active or queued training entry. If entry_id is omitted, cancels the most recent one."
)
async def training_cancel(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
    entry_id: int | None = Query(None, description="Specific training entry ID to cancel"),
):
    return await TrainingService(db).cancel_training(hero_id, user['user_id'], entry_id)


@router.post(
    "/{hero_id}/training/claim",
    response_model=TrainingQueueOut,
    summary="Claim completed training",
    description="Claims a finished training entry and applies its rewards. If entry_id is omitted, claims the oldest running entry."
)
async def training_claim(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
    entry_id: int | None = Query(None, description="Specific training entry ID to claim"),
):
    return await TrainingService(db).claim_training(hero_id, user['user_id'], entry_id)


@router.get(
    "/{hero_id}/training",
    response_model=TrainingQueueResponse,
    summary="Get training queue",
    description="Returns all active and recently completed training entries for the hero."
)
async def training_list(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    return await TrainingService(db).get_training_queue(hero_id, user['user_id'])


@router.post(
    "/{hero_id}/resurrect",
    response_model=ResurrectionEventOut,
    summary="Resurrect a dead hero",
    description="Use a rare artifact to revive a dead hero. Each hero may only be resurrected a limited number of times before permanent death."
)
async def resurrect_hero(
    hero_id: int,
    body: ResurrectRequest,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    return await ResurrectionService(db).resurrect(
        hero_id, user['user_id'], body.artifact_code,
    )


@router.get(
    "/{hero_id}/status",
    response_model=HeroStatusResponse,
    summary="Get hero status",
    description="Returns the hero's current condition, health state, and resurrection history."
)
async def hero_status(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    return await ResurrectionService(db).get_status(hero_id, user['user_id'])
