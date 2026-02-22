# app/routers/inventory.py

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.schemas.inventory import StashCreate, StashOut
from app.services.inventory import StashService
from app.database.session import get_session
from app.auth import get_current_user_info

router = APIRouter(prefix="/inventory", tags=["Inventory"])

@router.post(
    "/",
    response_model=StashOut,
    summary="Add item to user's stash",
    description="Adds an item to the user's stash."
)
async def add_to_stash(data: StashCreate, db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    service = StashService(db)
    item = await service.add_to_stash(user_id=current_user["user_id"], item_id=data.item_id, quantity=data.quantity)
    return StashOut.from_orm(item)

@router.get(
    "/",
    response_model=List[StashOut],
    summary="Get user's stash",
    description="Returns a list of all items in the user's stash. Returns 404 if stash is empty."
)
async def read_stash(db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    service = StashService(db)
    items = await service.list_stash(user_id=current_user["user_id"])
    if not items:
        raise HTTPException(404, "Stash is empty")
    return [StashOut.from_orm(i) for i in items]
