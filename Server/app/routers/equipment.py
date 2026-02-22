from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
from app.schemas.equipment import EquipmentCreate, EquipmentOut
from app.services.equipment import EquipmentService
from app.database.session import get_session
from app.auth import get_current_user_info
from app.database.models.hero import Hero
from app.database.models.models import Equipment
from app.services.hero import HeroService
from app.schemas.item import SlotType

router = APIRouter(prefix="/equipment", tags=["Equipment"])

def get_equipment_service(db: AsyncSession = Depends(get_session)):
    return EquipmentService(db)

@router.post("/", response_model=EquipmentOut, summary="Equip an item to hero", description="Equips an item to the specified hero in the given slot. Only the owner of the hero can equip items.")
async def equip_item(data: EquipmentCreate, db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    hero = await db.get(Hero, data.hero_id)
    if not hero or hero.owner_id != current_user["user_id"]:
        raise HTTPException(403, "Forbidden: You do not own this hero")
    service = EquipmentService(db)
    equipment = await service.equip_item(hero_id=data.hero_id, user_id=current_user["user_id"], item_id=data.item_id, slot=data.slot)
    return EquipmentOut.from_orm(equipment)

@router.delete("/{equipment_id}", summary="Unequip item from hero", description="Removes an equipped item from the hero and returns it to inventory. Only the owner of the hero can unequip items.")
async def unequip_item(equipment_id: int, db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    equipment = await db.get(Equipment, equipment_id)
    if not equipment:
        raise HTTPException(404, "Equipment not found")
    hero = await db.get(Hero, equipment.hero_id)
    if not hero or hero.owner_id != current_user["user_id"]:
        raise HTTPException(403, "Forbidden")
    service = EquipmentService(db)
    await service.unequip_item(hero_id=equipment.hero_id, user_id=current_user["user_id"], slot=equipment.slot)
    return {"detail": "Item unequipped successfully"}

@router.get("/", response_model=List[EquipmentOut], summary="Get equipped items for current user", description="Returns a list of all equipped items for all heroes owned by the authenticated user.")
async def list_equipment(db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    heroes = await HeroService(db).list_heroes(current_user["user_id"])
    hero_ids = [h.id for h in heroes]
    service = EquipmentService(db)
    equipment_list = await service.list_equipment(hero_ids)
    return [EquipmentOut.from_orm(eq) for eq in equipment_list]

@router.get("/hero/{hero_id}", response_model=List[EquipmentOut], summary="Get equipped items for a hero", description="Returns a list of all equipped items for a specific hero. Only the owner of the hero can view equipment.")
async def get_hero_equipment(hero_id: int, db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    hero = await db.get(Hero, hero_id)
    if not hero or hero.owner_id != current_user["user_id"]:
        raise HTTPException(403, "Forbidden: You do not own this hero")
    service = EquipmentService(db)
    equipment_list = await service.get_equipment(hero_id)
    return [EquipmentOut.from_orm(eq) for eq in equipment_list] 