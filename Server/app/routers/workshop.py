from fastapi import APIRouter, Depends, HTTPException
from typing import List, Dict, Any
from sqlalchemy.ext.asyncio import AsyncSession
from app.services.craft import CraftService
from app.schemas.craft import CraftRecipeOut, CraftQueueOut, CraftedItemOut, DisenchantOut
from app.database.models.craft import CraftQueue
from app.database.session import get_session
from app.auth import get_current_user_info

router = APIRouter(prefix="/workshop", tags=["Workshop"])

@router.get("/available", response_model=List[CraftRecipeOut])
async def workshop_available(db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    service = CraftService(db)
    recipes = await service.get_recipes()
    uid = current_user["user_id"]
    available = []
    for r in recipes:
        if await service.can_craft(uid, r):
            available.append(r)
    return available

@router.get("/queue", response_model=List[CraftQueueOut])
async def workshop_queue(db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    uid = current_user["user_id"]
    result = await db.execute(CraftQueue.__table__.select().where(CraftQueue.user_id == uid))
    return result.scalars().all()

@router.post("/craft/{recipe_id}", response_model=CraftQueueOut)
async def workshop_craft(recipe_id: int, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    try:
        return await CraftService(db).start_craft(current_user["user_id"], recipe_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/finish/{queue_id}", response_model=CraftedItemOut)
async def workshop_finish(queue_id: int, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    try:
        return await CraftService(db).finish_craft(queue_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/disenchant/{crafted_id}", response_model=DisenchantOut)
async def workshop_disenchant(crafted_id: int, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    try:
        return await CraftService(db).disenchant_item(current_user["user_id"], crafted_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) 