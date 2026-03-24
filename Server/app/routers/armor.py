"""
Armor catalog, set-bonus definitions, and player armor inventory.
"""
from __future__ import annotations
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.auth import get_current_user_info
from app.database.session import get_session
from app.database.models.armor import ArmorItem, ArmorSetBonus, PlayerArmorInventory

router = APIRouter(prefix="/armor", tags=["Armor"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class ArmorItemOut(BaseModel):
    id:          int
    name:        str
    slot:        str
    tier:        int
    set_type:    str
    is_starter:  bool
    bonuses:     Dict[str, Any]
    description: str

    model_config = {"from_attributes": True}


class SetBonusOut(BaseModel):
    set_type:        str
    pieces_required: int
    bonuses:         Dict[str, Any]
    description:     str

    model_config = {"from_attributes": True}


class PlayerArmorOut(BaseModel):
    id:            int
    armor_item_id: int
    hero_id:       Optional[int]
    is_equipped:   bool
    quality:       str
    item:          ArmorItemOut

    model_config = {"from_attributes": True}


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("/catalog", response_model=List[ArmorItemOut],
            summary="Full armor item catalog")
async def armor_catalog(
    tier:     Optional[int] = None,
    set_type: Optional[str] = None,
    db: AsyncSession = Depends(get_session),
):
    stmt = select(ArmorItem)
    if tier is not None:
        stmt = stmt.where(ArmorItem.tier == tier)
    if set_type:
        stmt = stmt.where(ArmorItem.set_type == set_type)
    result = await db.execute(stmt.order_by(ArmorItem.tier, ArmorItem.set_type, ArmorItem.slot))
    items = result.scalars().all()
    return [
        ArmorItemOut(
            id=i.id, name=i.name,
            slot=i.slot.value if hasattr(i.slot, "value") else str(i.slot),
            tier=i.tier,
            set_type=i.set_type.value if hasattr(i.set_type, "value") else str(i.set_type),
            is_starter=i.is_starter,
            bonuses=i.bonuses or {},
            description=i.description or "",
        )
        for i in items
    ]


@router.get("/sets", response_model=List[SetBonusOut],
            summary="All set-bonus definitions")
async def set_bonuses(db: AsyncSession = Depends(get_session)):
    result = await db.execute(
        select(ArmorSetBonus).order_by(ArmorSetBonus.set_type, ArmorSetBonus.pieces_required)
    )
    rows = result.scalars().all()
    return [
        SetBonusOut(
            set_type=r.set_type.value if hasattr(r.set_type, "value") else str(r.set_type),
            pieces_required=r.pieces_required,
            bonuses=r.bonuses or {},
            description=r.description or "",
        )
        for r in rows
    ]


@router.get("/my", response_model=List[PlayerArmorOut],
            summary="Current player's armor inventory")
async def my_armor(
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    result = await db.execute(
        select(PlayerArmorInventory)
        .where(PlayerArmorInventory.user_id == user["user_id"])
        .options(selectinload(PlayerArmorInventory.armor_item))
    )
    rows = result.scalars().all()
    out = []
    for r in rows:
        item = r.armor_item
        out.append(PlayerArmorOut(
            id=r.id,
            armor_item_id=r.armor_item_id,
            hero_id=r.hero_id,
            is_equipped=r.is_equipped,
            quality=r.quality,
            item=ArmorItemOut(
                id=item.id, name=item.name,
                slot=item.slot.value if hasattr(item.slot, "value") else str(item.slot),
                tier=item.tier,
                set_type=item.set_type.value if hasattr(item.set_type, "value") else str(item.set_type),
                is_starter=item.is_starter,
                bonuses=item.bonuses or {},
                description=item.description or "",
            ),
        ))
    return out


@router.post("/equip/{inventory_id}", summary="Equip an armor piece on a hero")
async def equip_armor(
    inventory_id: int,
    hero_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    row = await db.get(PlayerArmorInventory, inventory_id)
    if not row or row.user_id != user["user_id"]:
        raise HTTPException(404, "Armor piece not found")
    row.hero_id = hero_id
    row.is_equipped = True
    await db.commit()
    return {"ok": True}


@router.post("/unequip/{inventory_id}", summary="Unequip an armor piece")
async def unequip_armor(
    inventory_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    row = await db.get(PlayerArmorInventory, inventory_id)
    if not row or row.user_id != user["user_id"]:
        raise HTTPException(404, "Armor piece not found")
    row.is_equipped = False
    row.hero_id = None
    await db.commit()
    return {"ok": True}
