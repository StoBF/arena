from pydantic import BaseModel, Field, ConfigDict
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
    name: str = Field(...)
    description: Optional[str] = Field(None)
    type: ItemType = Field(...)
    slot_type: SlotType = Field(...)
    bonus_strength: Optional[int] = Field(0)
    bonus_agility: Optional[int] = Field(0)
    bonus_intelligence: Optional[int] = Field(0)

class ItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    name: str = Field(...)
    description: Optional[str] = Field(None)
    type: ItemType = Field(...)
    slot_type: SlotType = Field(...)
    bonus_strength: int = Field(...)
    bonus_agility: int = Field(...)
    bonus_intelligence: int = Field(...)
