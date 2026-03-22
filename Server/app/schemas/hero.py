# app/schemas/hero.py
"""
Pydantic schemas for the v2 hero system.

Removed from v1:
  PerkOut, HeroAbilityOut, HeroAbilityCreate, HeroArchetype imports,
  TrainingStartRequest, TrainingQueueOut, TrainingQueueResponse,
  PerkUpgradeRequest, AbilityType/AbilityDomain/TrainingType/TrainingStatus
"""

from pydantic import BaseModel, Field, ConfigDict
from typing import Literal, List, Optional, Dict, Any
from datetime import datetime

from app.database.models.hero import (
    BodyPartStatus, HeroCondition, HeroRole,
    SkillFamily, CastType, TargetType, TargetTeam,
)


# ─── Stats schemas ───────────────────────────────────────────────────────

class HeroStatsOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    health: int = 100
    stamina: int = 100
    defense: int = 10
    vision: int = 10
    speed: int = 10
    agility: int = 10
    luck: int = 5
    willpower: int = 5


class DerivedStatsOut(BaseModel):
    """Computed from primary stats + generation level + equipment. Never stored."""
    max_hp: int = 0
    initiative: int = 0
    accuracy: int = 0
    evasion: int = 0
    critical_chance: float = 0.0
    critical_resistance: float = 0.0
    armor_efficiency: float = 0.0
    recovery_speed: float = 0.0
    trauma_resistance: float = 0.0


# ─── Skill schemas ───────────────────────────────────────────────────────

class SkillEffectOut(BaseModel):
    """One normalised effect row attached to a hero's skill instance."""
    model_config = ConfigDict(from_attributes=True)

    id: int
    effect_type: str          # e.g. "damage", "heal", "stun", "dot", "buff", "drain"
    effect_target: str        # e.g. "health", "stamina", "defense", "speed"
    effect_value: float = 0.0
    effect_scaling_json: Optional[str] = None


class SkillCatalogOut(BaseModel):
    """
    Canonical skill metadata from skills_catalog.
    This is the rich reference data the client needs for display —
    names, descriptions, category, targeting, cast behaviour, costs,
    and boolean flags — so it never needs to hardcode anything.

    Localization: display_name, description_short, and description_full
    are stored per-locale in the catalog; the server returns the values
    matching the hero's locale.
    """
    model_config = ConfigDict(from_attributes=True)

    skill_code: str
    display_name: str
    skill_family: SkillFamily       # COMBAT / BUFF / DEBUFF / TRANSFER / CONTROL
    description_short: Optional[str] = None
    description_full: Optional[str] = None

    # Targeting
    target_type: TargetType         # SELF / SINGLE / AOE / TEAM / ALL
    target_team: TargetTeam         # ALLY / ENEMY / ANY
    cast_type: CastType             # INSTANT / CAST / CHANNEL / AURA / TRIGGER / LINK

    # Base values (reference — hero instance may override)
    stamina_cost_base: int = 0
    cooldown_base: float = 0.0
    duration_base: float = 0.0
    power_base: int = 0
    radius_base: float = 0.0

    # Behaviour flags
    requires_vision: bool = True
    is_redirectable: bool = False
    is_interruptible: bool = True
    is_stealable: bool = False
    is_upgradable: bool = True
    has_kill_trigger: bool = False

    # Control
    control_tier: Optional[int] = None

    # Extra config
    metadata_json: Optional[str] = None


class SkillDetailOut(BaseModel):
    """
    Full skill payload for a hero: instance-specific values
    + embedded catalog metadata + normalised effects.

    The client receives everything needed to render skill tooltips,
    action bars, and targeting UI without any hardcoded skill data.
    """
    model_config = ConfigDict(from_attributes=True)

    # Identity
    id: int
    skill_code: str
    slot_index: int = 0
    is_signature: bool = False
    source_type: str = "GENERATION"

    # Instance values (scaled from catalog base during generation)
    generation_level: int = 1
    cost_generation_level: int = 1
    power_value: int = 0
    duration_value: float = 0.0
    cooldown_value: float = 0.0
    stamina_cost_value: int = 0
    radius_value: float = 0.0
    upgrade_count: int = 0
    payload_json: Optional[str] = None

    # Rich catalog metadata (never null if data is consistent)
    catalog: Optional[SkillCatalogOut] = None

    # Normalised effects attached to this instance
    effects: List[SkillEffectOut] = Field(default_factory=list)


# ─── Tag schemas ─────────────────────────────────────────────────────────

class HeroTagOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    tag_code: str
    tag_group: str
    tag_value: Optional[float] = None


# ─── Hidden trait schemas ────────────────────────────────────────────────

class HeroHiddenTraitOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    trait_code: str
    trait_value: float = 0.0


# ─── Generation layer schemas ───────────────────────────────────────────

class HeroGenerationLayerOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    layer_index: int
    success: bool
    success_rate_used: float
    roll_value: float
    payload_json: Optional[str] = None


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


# ─── History / titles / combat stats ─────────────────────────────────────

class HeroHistoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    event_type: str
    event_data: Optional[str] = None
    created_at: Optional[datetime] = None


class CombatStatsOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    total_kills: int = 0
    boss_kills: int = 0
    arena_wins: int = 0
    battles: int = 0
    damage_dealt: int = 0
    damage_taken: int = 0
    last_battle_at: Optional[datetime] = None


class HeroTitleOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title_code: str
    title_name: str
    awarded_at: Optional[datetime] = None
    source: Optional[str] = None


# ─── Hero Out (flat, no relationships) ───────────────────────────────────

class HeroOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    hero_generation_level: int = 1
    generation_version: int = 2

    # Roles
    primary_role: Optional[str] = None
    secondary_role: Optional[str] = None

    # Core coefficients
    hero_coherence: float = 1.0
    stability: float = 1.0
    control_susceptibility: float = 1.0
    transfer_conductivity: float = 1.0
    execution_resonance: float = 1.0
    affinity_bias: float = 0.0

    # HP state
    current_hp: int = 100
    max_hp_override: Optional[int] = None
    condition: HeroCondition = HeroCondition.HEALTHY
    resurrection_count: int = 0

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
    stats: Optional[HeroStatsOut] = None
    skills: List[SkillDetailOut] = Field(default_factory=list)
    tags: List[HeroTagOut] = Field(default_factory=list)
    body_parts: List[BodyPartOut] = Field(default_factory=list)
    titles: List[HeroTitleOut] = Field(default_factory=list)
    history: List[HeroHistoryOut] = Field(default_factory=list)
    derived_stats: Optional[DerivedStatsOut] = None


# ─── Hero Generate Request ───────────────────────────────────────────────

class HeroGenerateRequest(BaseModel):
    locale: Literal["en", "pl", "uk"] = Field("en")
    seed: Optional[str] = Field(None, description="Hex seed for deterministic generation")


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


class HeroStoryResponse(BaseModel):
    """Full combat history + titles for a hero."""
    hero_id: int
    combat_stats: CombatStatsOut
    titles: List[HeroTitleOut] = Field(default_factory=list)
