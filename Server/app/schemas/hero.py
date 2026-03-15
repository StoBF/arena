# app/schemas/hero.py
from pydantic import BaseModel, Field, ConfigDict, computed_field
from typing import Literal, List, Optional, Dict, Any
from datetime import datetime
from decimal import Decimal

from app.database.models.hero import HeroArchetype, AbilityType, AbilityDomain, BodyPartStatus, TrainingType, TrainingStatus, HeroCondition


# ─── Perk schemas ────────────────────────────────────────────────────────

class PerkOut(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    effect_type: Optional[str] = None
    max_level: int
    modifiers: Dict[str, Any] = Field(default_factory=dict)
    affected: List[str] = Field(default_factory=list)
    perk_level: int


# ─── Ability schemas ─────────────────────────────────────────────────────

class HeroAbilityOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    ability_code: str
    ability_name: str
    ability_type: AbilityType
    ability_domain: AbilityDomain
    ability_level: int = 1
    is_active: bool = True
    metadata_json: Optional[str] = None
    acquired_at: Optional[datetime] = None
    source: Optional[str] = None


class HeroAbilityCreate(BaseModel):
    ability_code: str = Field(..., max_length=80)
    ability_name: str = Field(..., max_length=120)
    ability_type: AbilityType
    ability_domain: AbilityDomain
    ability_level: int = Field(1, ge=1)
    metadata_json: Optional[str] = None
    source: Optional[str] = None


# ─── Derived stats (calculated, never stored) ────────────────────────────

class DerivedStats(BaseModel):
    """Computed from primary stats + level + equipment. Not persisted."""
    max_hp: int = 0
    initiative: int = 0
    accuracy: int = 0
    evasion: int = 0
    critical_chance: float = 0.0
    critical_resistance: float = 0.0
    armor_efficiency: float = 0.0
    recovery_speed: float = 0.0
    trauma_resistance: float = 0.0


# ─── Body part schemas ────────────────────────────────────────────────────

class BodyPartOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    part_name: str
    max_hp: int
    current_hp: int
    armor: int
    status: BodyPartStatus
    updated_at: Optional[datetime] = None


class HeroBodyResponse(BaseModel):
    """Full body state for a hero."""
    hero_id: int
    parts: List[BodyPartOut] = Field(default_factory=list)


# ─── Hero Create ─────────────────────────────────────────────────────────

class HeroCreate(BaseModel):
    name: str = Field(...)
    archetype: Optional[HeroArchetype] = None
    # Primary stats (optional – generation will roll them if omitted)
    strength: Optional[int] = None
    perception: Optional[int] = None
    endurance: Optional[int] = None
    intelligence: Optional[int] = None
    agility: Optional[int] = None
    luck: Optional[int] = None
    willpower: Optional[int] = None
    level: Optional[int] = None
    experience: Optional[int] = None
    is_training: Optional[bool] = None
    training_end_time: Optional[datetime] = None


# ─── Hero Out (flat, no relationships) ───────────────────────────────────

class HeroOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    generation: int
    nickname: str
    archetype: Optional[HeroArchetype] = None

    # Primary stats
    strength: int = 0
    perception: int = 0
    endurance: int = 0
    intelligence: int = 0
    agility: int = 0
    luck: int = 0
    willpower: int = 0

    # HP state
    current_hp: int = 100
    max_hp_override: Optional[int] = None
    condition: HeroCondition = HeroCondition.HEALTHY
    resurrection_count: int = 0

    # Progression
    level: int = 1
    experience: int = 0

    # Training
    is_training: bool = False
    training_end_time: Optional[datetime] = None
    training_stat: Optional[str] = None
    training_sessions_completed: int = 0

    # Death / combat
    is_dead: bool = False
    dead_at: Optional[datetime] = None
    death_cause: Optional[str] = None
    is_permadead: bool = False
    total_kills: int = 0
    total_deaths: int = 0
    total_absorbed: int = 0

    # Meta
    locale: Literal["en", "pl", "uk"] = "en"
    is_deleted: bool = False
    deleted_at: Optional[datetime] = None
    is_on_auction: bool = False
    created_at: Optional[datetime] = None


# ─── Hero Read (with relationships + derived stats) ──────────────────────

class HeroRead(HeroOut):
    perks: List[PerkOut] = Field(default_factory=list)
    abilities: List[HeroAbilityOut] = Field(default_factory=list)
    derived_stats: Optional[DerivedStats] = None


# ─── Hero Generate Request ───────────────────────────────────────────────

class HeroGenerateRequest(BaseModel):
    generation: int = Field(..., ge=1, le=10)
    currency: Decimal = Field(..., ge=Decimal('0'), decimal_places=2)
    locale: Literal["en", "pl", "uk"] = Field("en")
    archetype: Optional[HeroArchetype] = Field(None, description="Preferred archetype; random if omitted")


# ─── Training Request ─────────────────────────────────────────────────────

class TrainRequest(BaseModel):
    training_stat: str = Field(..., description="Primary stat to train (strength, perception, endurance, intelligence, agility, luck, willpower)")
    duration_minutes: int = Field(60, ge=1, le=1440, description="Training duration in minutes (max 24h)")


# ─── Training Queue schemas ──────────────────────────────────────────────

class TrainingStartRequest(BaseModel):
    training_type: TrainingType = Field(..., description="attribute | discipline | ability")
    training_target: str = Field(..., max_length=80, description="Stat name, discipline code, or ability code")
    target_level: int = Field(1, ge=1, le=100, description="Desired level to train to")
    room_slot: int = Field(0, ge=0, le=2, description="Training room slot (0-2)")


class TrainingQueueOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    hero_id: int
    training_type: TrainingType
    training_target: str
    current_level: int
    target_level: int
    started_at: Optional[datetime] = None
    ends_at: Optional[datetime] = None
    status: TrainingStatus
    room_slot: int
    efficiency: float = 1.0
    time_remaining_seconds: Optional[int] = None


class TrainingQueueResponse(BaseModel):
    hero_id: int
    slots: List[TrainingQueueOut] = Field(default_factory=list)


# ─── Combat stats schemas ────────────────────────────────────────────────

class CombatStatsOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    total_kills: int = 0
    boss_kills: int = 0
    arena_wins: int = 0
    battles: int = 0
    damage_dealt: int = 0
    damage_taken: int = 0
    last_battle_at: Optional[datetime] = None


# ─── Title schemas ──────────────────────────────────────────────────────

class HeroTitleOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title_code: str
    title_name: str
    awarded_at: Optional[datetime] = None
    source: Optional[str] = None


class HeroStoryResponse(BaseModel):
    """Full combat history + titles for a hero."""
    hero_id: int
    combat_stats: CombatStatsOut
    titles: List[HeroTitleOut] = Field(default_factory=list)


# ─── Perk Upgrade ────────────────────────────────────────────────────────

class PerkUpgradeRequest(BaseModel):
    perk_id: int


# ─── Resurrection schemas ────────────────────────────────────────────────

class ResurrectRequest(BaseModel):
    artifact_code: str = Field(..., max_length=120, description="Artifact used: 'phoenix_core' or 'heart_of_reversal'")


class ResurrectionEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    hero_id: int
    artifact_used: str
    revived_at: Optional[datetime] = None
    side_effects_json: Optional[str] = None
    condition_before: HeroCondition
    condition_after: HeroCondition
    hp_restored_to: int = 0


class HeroStatusResponse(BaseModel):
    hero_id: int
    name: str
    condition: HeroCondition
    is_dead: bool
    is_permadead: bool
    current_hp: int
    resurrection_count: int
    death_cause: Optional[str] = None
    dead_at: Optional[datetime] = None
