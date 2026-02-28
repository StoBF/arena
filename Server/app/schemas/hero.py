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
    name: str = Field(...)
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

    id:         int = Field(...)
    name:       str = Field(...)
    generation: int = Field(...)
    nickname:   str = Field(...)
    strength:   int = Field(...)
    agility:    int = Field(...)
    endurance:  int = Field(...)
    speed:      int = Field(...)
    health:     int = Field(...)
    defense:    int = Field(...)
    luck:       int = Field(...)
    field_of_view: int = Field(...)
    level:      int = Field(...)
    experience: int = Field(...)
    is_training: bool = Field(...)
    training_end_time: Optional[datetime] = Field(None)
    is_dead: Optional[bool] = Field(False)
    dead_until: Optional[datetime] = Field(None)
    locale:     Literal["en","pl","uk"] = Field(...)
    is_deleted: bool = Field(...)
    deleted_at: Optional[datetime] = Field(None)
    is_on_auction: bool = Field(...)

# Схема відповіді з перками
class HeroRead(HeroOut):
    perks: List[PerkOut] = Field(default_factory=list)

# Схема для генерації героя (POST /heroes/generate)
class HeroGenerateRequest(BaseModel):
    generation: int = Field(..., ge=1, le=10)
    currency:   Decimal = Field(..., ge=Decimal('0'), decimal_places=2)
    locale:     Literal["en","pl","uk"] = Field("en")

class PerkUpgradeRequest(BaseModel):
    perk_id: int
