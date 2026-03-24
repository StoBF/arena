"""
Player resource inventory endpoints.
"""
from __future__ import annotations
from typing import List

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.auth import get_current_user_info
from app.database.session import get_session
from app.database.models.battle_room import PlayerResourceInventory
from app.database.models.resource import GameResource

router = APIRouter(prefix="/resources", tags=["Resources"])


class ResourceEntryOut(BaseModel):
    resource_id: int
    code: str
    name: str
    category: str
    quantity: int


@router.get("/my", response_model=List[ResourceEntryOut],
            summary="List current player's resource inventory")
async def my_resources(
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    user_id = user["user_id"]
    result = await db.execute(
        select(PlayerResourceInventory)
        .where(PlayerResourceInventory.user_id == user_id)
        .options(selectinload(PlayerResourceInventory.resource))
    )
    rows = result.scalars().all()
    return [
        ResourceEntryOut(
            resource_id=r.resource_id,
            code=r.resource.code,
            name=r.resource.name,
            category=r.resource.category.value if hasattr(r.resource.category, "value") else str(r.resource.category),
            quantity=r.quantity,
        )
        for r in rows
    ]


@router.get("/catalog", summary="Full resource catalog")
async def resource_catalog(db: AsyncSession = Depends(get_session)):
    result = await db.execute(select(GameResource).order_by(GameResource.category, GameResource.code))
    resources = result.scalars().all()
    return [
        {
            "id":          r.id,
            "code":        r.code,
            "name":        r.name,
            "category":    r.category.value if hasattr(r.category, "value") else str(r.category),
            "source":      r.source,
            "description": r.description,
        }
        for r in resources
    ]
