from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
from app.schemas.item import ItemCreate, ItemOut
from app.services.item import ItemService
from app.database.session import get_session
from app.auth import get_current_user, get_current_user_info

router = APIRouter(prefix="/items", tags=["Items"])

@router.post(
    "/",
    response_model=ItemOut,
    summary="Create a new item",
    description="Creates a new item with the specified attributes. Only authenticated users can create items."
)
async def create(data: ItemCreate, db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    service = ItemService(db)
    item = await service.create_item(**data.dict())
    return ItemOut.from_orm(item)

@router.get(
    "/",
    response_model=List[ItemOut],
    summary="List all items",
    description="Returns a list of all items available in the system. Only authenticated users can view items."
)
async def read_all(db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    service = ItemService(db)
    items = await service.list_items()
    return [ItemOut.from_orm(i) for i in items]

@router.get(
    "/{item_id}",
    response_model=ItemOut,
    summary="Get item by ID",
    description="Returns detailed information about a specific item by its ID. Only authenticated users can view items."
)
async def read_one(item_id: int, db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    service = ItemService(db)
    item = await service.get_item(item_id)
    if not item:
        raise HTTPException(404, "Item not found")
    return ItemOut.from_orm(item)

@router.put(
    "/{item_id}",
    response_model=ItemOut,
    summary="Update an item",
    description="Updates the attributes of an existing item by its ID. Only authenticated users can update items."
)
async def update(item_id: int, data: ItemCreate, db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    service = ItemService(db)
    updated = await service.update_item(item_id, **data.dict())
    if not updated:
        raise HTTPException(404, "Item not found")
    return ItemOut.from_orm(updated)

@router.delete(
    "/{item_id}",
    response_model=ItemOut,
    summary="Delete an item",
    description="Deletes an item by its ID. Only authenticated users can delete items."
)
async def remove(item_id: int, db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    service = ItemService(db)
    deleted = await service.delete_item(item_id)
    if not deleted:
        raise HTTPException(404, "Item not found")
    return ItemOut.from_orm(deleted)
