# app/routers/craft.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.services.craft import CraftService
from app.schemas.craft import CraftRecipeOut, CraftStartIn, CraftQueueOut, CraftedItemOut, DisenchantIn, DisenchantOut
from app.database.models.craft import CraftQueue
from app.database.session import get_session
from app.auth import get_current_user_info

router = APIRouter(prefix="/craft", tags=["craft"])

@router.get("/recipes", response_model=List[CraftRecipeOut])
async def list_recipes(db: AsyncSession = Depends(get_session)):
    """Return all craft recipes."""
    return await CraftService(db).get_recipes()

@router.post("/start", response_model=CraftQueueOut)
async def start_craft(
    payload: CraftStartIn,
    current_user=Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session)
):
    """Begin crafting a recipe."""
    try:
        return await CraftService(db).start_craft(current_user["user_id"], payload.recipe_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/finish", response_model=CraftedItemOut)
async def finish_craft(
    payload: CraftQueueOut,
    current_user=Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session)
):
    """Complete a craft once ready."""
    try:
        return await CraftService(db).finish_craft(payload.id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/disenchant", response_model=DisenchantOut)
async def disenchant_item(
    payload: DisenchantIn,
    current_user=Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session)
):
    """Disenchant a crafted item for resources."""
    try:
        return await CraftService(db).disenchant_item(current_user["user_id"], payload.crafted_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/available", response_model=List[CraftRecipeOut])
async def available_recipes(
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    """List recipes the user currently has materials for."""
    service = CraftService(db)
    recipes = await service.get_recipes()
    can_list = []
    uid = current_user["user_id"]
    for r in recipes:
        if await service.can_craft(uid, r):
            can_list.append(r)
    return can_list

@router.get("/queue", response_model=List[CraftQueueOut])
async def get_craft_queue(
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    """Get the user's current craft queue entries."""
    uid = current_user["user_id"]
    result = await db.execute(CraftQueue.__table__.select().where(CraftQueue.user_id == uid))
    return result.scalars().all() 