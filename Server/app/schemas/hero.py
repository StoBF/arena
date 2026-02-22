# app/schemas/hero.py
from pydantic import BaseModel, Field
from pydantic import ConfigDict
from typing import Literal, List, Optional, Dict, Any
from datetime import datetime
from decimal import Decimal

# Модель для перків
class PerkOut(BaseModel):
    id: int
    name: str
    description: Optional[str]
    effect_type: Optional[str]
    max_level: int
    modifiers: Dict[str, Any] = Field(default_factory=dict)
    affected: List[str] = Field(default_factory=list)
    perk_level: int

# Схема для створення звичайного героя
class HeroCreate(BaseModel):
    name: str = Field(..., example="Arthas")
    # Нові атрибути для тестів/адмінки (опціонально)
    strength: Optional[int] = None
    agility: Optional[int] = None
    endurance: Optional[int] = None
    speed: Optional[int] = None
    health: Optional[int] = None
    defense: Optional[int] = None
    luck: Optional[int] = None
    field_of_view: Optional[int] = None
    level: Optional[int] = None
    experience: Optional[int] = None
    is_training: Optional[bool] = None
    training_end_time: Optional[datetime] = None

# Схема відповіді без перків (наприклад, для Create/Update)
class HeroOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id:         int = Field(..., example=1)
    name:       str = Field(..., example="Arthas")
    generation: int = Field(..., example=2)
    nickname:   str = Field(..., example="the Brave")
    strength:   int = Field(..., example=15)
    agility:    int = Field(..., example=12)
    endurance:  int = Field(..., example=14)
    speed:      int = Field(..., example=10)
    health:     int = Field(..., example=100)
    defense:    int = Field(..., example=5)
    luck:       int = Field(..., example=3)
    field_of_view: int = Field(..., example=10)
    level:      int = Field(..., example=1)
    experience: int = Field(..., example=0)
    is_training: bool = Field(..., example=False)
    training_end_time: Optional[datetime] = Field(None, example=None)
    is_dead: Optional[bool] = Field(False, example=False)
    dead_until: Optional[datetime] = Field(None, example=None)
    locale:     Literal["en","pl","uk"] = Field(..., example="en")
    is_deleted: bool = Field(..., example=False)
    deleted_at: Optional[datetime] = Field(None, example=None)
    is_on_auction: bool = Field(..., example=False)

# Схема відповіді з перками
class HeroRead(HeroOut):
    perks: List[PerkOut] = Field(default_factory=list)

# Схема для генерації героя (POST /heroes/generate)
class HeroGenerateRequest(BaseModel):
    generation: int = Field(..., ge=1, le=10, example=2)
    currency:   Decimal = Field(..., ge=Decimal('0'), decimal_places=2, example="100.00")
    locale:     Literal["en","pl","uk"] = Field("en", example="en")

class PerkUpgradeRequest(BaseModel):
    perk_id: int
