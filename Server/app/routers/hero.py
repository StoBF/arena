from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
from app.schemas.hero import (
    HeroRead, HeroGenerateRequest,
    HeroBodyResponse, BodyPartOut,
    ResurrectRequest, ResurrectionEventOut, HeroStatusResponse,
)
from app.schemas.pagination import HeroesPaginatedResponse
from app.services.hero import HeroService
from app.services.resurrection import ResurrectionService
from app.database.session import get_session
from app.auth import get_current_user, get_current_user_info
from app.core.redis_cache import redis_cache

router = APIRouter(prefix="/heroes", tags=["Heroes"])


async def _serialize_hero(service: HeroService, hero_or_model) -> HeroRead:
    if isinstance(hero_or_model, HeroRead):
        return hero_or_model
    return await service.get_hero_full(hero_or_model.id)


@router.get(
    "/",
    response_model=HeroesPaginatedResponse,
    summary="Get all heroes for the current user",
    description="Returns a paginated list of all heroes belonging to the authenticated user.",
)
async def read_heroes(
    limit: int = Query(10, ge=1, le=100, description="Items per page (max 100)"),
    offset: int = Query(0, ge=0, description="Items to skip"),
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    cache_key = f"heroes:{user['user_id']}:{limit}:{offset}"
    cached = await redis_cache.get(cache_key)
    if cached is not None:
        return cached

    hero_service = HeroService(db)
    result = await hero_service.list_heroes(user["user_id"], limit=limit, offset=offset)
    items = [
        await hero_service.get_hero_full(hero.id)
        for hero in result["items"]
    ]

    response = {
        "items": items,
        "total": result["total"],
        "limit": result["limit"],
        "offset": result["offset"],
    }
    await redis_cache.set(cache_key, response, expire=60)
    return response


@router.get(
    "/{hero_id}",
    response_model=HeroRead,
    summary="Get a specific hero by ID",
    description="Returns detailed information about a specific hero owned by the authenticated user.",
)
async def read_hero(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    hero_service = HeroService(db)
    # Check existence & ownership first
    hero_obj = await hero_service.get_hero(hero_id)
    if not hero_obj or hero_obj.owner_id != user["user_id"]:
        raise HTTPException(404, "Hero not found")
    return await hero_service.get_hero_full(hero_id)


@router.post(
    "/generate",
    response_model=HeroRead,
    summary="Generate a new hero",
    description="Generates a new hero for the authenticated user using the v2 generation engine.",
)
async def generate_hero(
    req: HeroGenerateRequest,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    hero_service = HeroService(db)
    hero = await hero_service.generate_and_store(user["user_id"], req)
    return await _serialize_hero(hero_service, hero)


@router.delete(
    "/{hero_id}",
    response_model=HeroRead,
    summary="Delete a hero",
    description="Marks a hero as deleted for the authenticated user.",
)
async def delete_hero(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    hero_service = HeroService(db)
    hero = await hero_service.delete_hero(hero_id, user["user_id"])
    return await _serialize_hero(hero_service, hero)


@router.post(
    "/{hero_id}/restore",
    response_model=HeroRead,
    summary="Restore a deleted hero",
    description="Restores a previously deleted hero for the authenticated user.",
)
async def restore_hero(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    hero_service = HeroService(db)
    hero = await hero_service.restore_hero(hero_id, user["user_id"])
    return await _serialize_hero(hero_service, hero)


@router.get(
    "/{hero_id}/body",
    response_model=HeroBodyResponse,
    summary="Get hero body parts",
    description="Returns the current state of all body parts for the specified hero.",
)
async def get_hero_body(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    hero_service = HeroService(db)
    hero = await hero_service.get_hero(hero_id, load_body_parts=True)
    if not hero or hero.owner_id != user["user_id"]:
        raise HTTPException(404, "Hero not found")
    parts = [
        BodyPartOut.model_validate(bp, from_attributes=True)
        for bp in (hero.body_parts or [])
    ]
    return HeroBodyResponse(hero_id=hero.id, parts=parts)


@router.post(
    "/{hero_id}/resurrect",
    response_model=ResurrectionEventOut,
    summary="Resurrect a dead hero",
    description="Use a rare artifact to revive a dead hero.",
)
async def resurrect_hero(
    hero_id: int,
    body: ResurrectRequest,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    return await ResurrectionService(db).resurrect(
        hero_id, user["user_id"], body.artifact_code,
    )


@router.get(
    "/{hero_id}/status",
    response_model=HeroStatusResponse,
    summary="Get hero status",
    description="Returns the hero's current condition, health state, and resurrection history.",
)
async def hero_status(
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    return await ResurrectionService(db).get_status(hero_id, user["user_id"])
