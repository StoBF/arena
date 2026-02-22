from pydantic import BaseModel, Field
from typing import Optional
from enum import Enum

class ItemType(str, Enum):
    equipment = "equipment"
    artifact = "artifact"
    resource = "resource"
    material = "material"
    consumable = "consumable"

class SlotType(str, Enum):
    weapon = "weapon"
    helmet = "helmet"
    spacesuit = "spacesuit"
    boots = "boots"
    artifact = "artifact"
    shield = "shield"
    gadget = "gadget"
    implant = "implant"
    utility_belt = "utility_belt"

class ItemCreate(BaseModel):
    name: str = Field(..., example="Excalibur")
    description: Optional[str] = Field(None, example="Legendary sword of King Arthur.")
    type: ItemType = Field(..., example="equipment")
    slot_type: SlotType = Field(..., example="weapon")
    bonus_strength: Optional[int] = Field(0, example=10)
    bonus_agility: Optional[int] = Field(0, example=5)
    bonus_intelligence: Optional[int] = Field(0, example=2)

class ItemOut(BaseModel):
    id: int = Field(..., example=1)
    name: str = Field(..., example="Excalibur")
    description: Optional[str] = Field(None, example="Legendary sword of King Arthur.")
    type: ItemType = Field(..., example="equipment")
    slot_type: SlotType = Field(..., example="weapon")
    bonus_strength: int = Field(..., example=10)
    bonus_agility: int = Field(..., example=5)
    bonus_intelligence: int = Field(..., example=2)

    class Config:
        from_attributes = True