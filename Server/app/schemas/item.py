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
    """Create an item.

    Field names match the v1 DB columns.  The ``item_stat_map`` module
    translates these to v2 stat keys at runtime so callers and the DB
    stay in sync without a migration.
    """
    name: str = Field(...)
    description: Optional[str] = Field(None)
    type: ItemType = Field(...)
    slot_type: SlotType = Field(...)
    bonus_strength: Optional[int] = Field(0)
    bonus_agility: Optional[int] = Field(0)
    bonus_intelligence: Optional[int] = Field(0)
    bonus_endurance: Optional[int] = Field(0)
    bonus_speed: Optional[int] = Field(0)
    bonus_health: Optional[int] = Field(0)
    bonus_defense: Optional[int] = Field(0)
    bonus_luck: Optional[int] = Field(0)

class ItemOut(BaseModel):
    """Serialise an Item row.

    Exposes all 8 bonus columns so the client can map them via
    ``ITEM_BONUS_STAT_MAP`` to the v2 stat keys.
    """
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    name: str = Field(...)
    description: Optional[str] = Field(None)
    type: ItemType = Field(...)
    slot_type: str = Field(...)
    bonus_strength: int = Field(0)
    bonus_agility: int = Field(0)
    bonus_intelligence: int = Field(0)
    bonus_endurance: int = Field(0)
    bonus_speed: int = Field(0)
    bonus_health: int = Field(0)
    bonus_defense: int = Field(0)
    bonus_luck: int = Field(0)
