from pydantic import BaseModel
from typing import List
from typing import Any, Optional
from datetime import datetime

class RaidDropItemOut(BaseModel):
    item_name: str
    chance: float

class RecipeDropOut(BaseModel):
    recipe_id: int
    chance: float

class RaidBossOut(BaseModel):
    id: int
    name: str
    gen_min: int
    gen_max: int
    loot_table: List[RaidDropItemOut]
    drop_recipes: List[RecipeDropOut] = []

    class Config:
        orm_mode = True

class ArenaInstanceOut(BaseModel):
    id: int
    user_id: int
    boss_id: Optional[int]
    wave: int
    mobs: List[Any]
    created_at: datetime
    is_active: bool

    class Config:
        orm_mode = True

class PvEBattleLogOut(BaseModel):
    id: int
    instance_id: int
    events: List[Any]
    outcome: str
    created_at: datetime

    class Config:
        orm_mode = True

class RewardOut(BaseModel):
    type: str
    id: int
    qty: Optional[int] = 1 