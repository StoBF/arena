from pydantic import BaseModel, Field
from app.schemas.item import SlotType

class EquipmentCreate(BaseModel):
    hero_id: int = Field(..., example=7)
    item_id: int = Field(..., example=101)
    slot: SlotType = Field(..., example="weapon")

class EquipmentOut(BaseModel):
    id: int
    hero_id: int
    item_id: int
    slot: SlotType
    class Config:
        from_attributes = True 