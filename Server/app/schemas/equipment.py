from pydantic import BaseModel, Field, ConfigDict
from app.schemas.item import SlotType

class EquipmentCreate(BaseModel):
    hero_id: int = Field(...)
    item_id: int = Field(...)
    slot: SlotType = Field(...)

class EquipmentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    hero_id: int
    item_id: int
    slot: SlotType