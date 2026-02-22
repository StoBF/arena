from pydantic import BaseModel, ConfigDict
from typing import List, Dict, Any, Optional
from datetime import datetime
from app.schemas.item import ItemType

class ResourceAmount(BaseModel):
    resource_id: int
    quantity: int

class CraftRecipeResourceOut(BaseModel):
    id: int
    resource_id: int
    quantity: int
    type: str  # 'pvp' або 'pve'
    model_config = ConfigDict(from_attributes=True)

class CraftRecipeOut(BaseModel):
    id: int
    name: str
    item_type: ItemType
    grade: int
    boss_id: Optional[int]
    drop_chance: float
    craft_time_sec: int
    resources: List[CraftRecipeResourceOut]
    model_config = ConfigDict(from_attributes=True)

class CraftedItemOut(BaseModel):
    id: int
    user_id: int
    result_item_id: Optional[int]
    item_type: ItemType
    grade: int
    is_mutated: bool
    recipe_id: int
    model_config = ConfigDict(from_attributes=True)

class CraftQueueOut(BaseModel):
    id: int
    user_id: int
    recipe_id: int
    ready_at: datetime
    model_config = ConfigDict(from_attributes=True)

class CraftStartIn(BaseModel):
    recipe_id: int

class DisenchantIn(BaseModel):
    crafted_id: int

class DisenchantOut(BaseModel):
    returned_resources: Dict[int, int]
    model_config = ConfigDict(from_attributes=True) 