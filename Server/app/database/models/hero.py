"""
Hero system models — v2 (role-based, skill catalog, no training/XP)

Tables managed by this module
─────────────────────────────
Core hero
  heroes                   Hero identity, roles, coefficients, state
  hero_stats               Current primary stat block (health/stamina/def/…)
  hero_generation_layers   Per-layer roll audit from generation levels 1..10
  hero_tags                Generated personality / style / affinity tags
  hero_hidden_traits       Hidden coefficients not exposed to UI

Skill system
  skills_catalog           Canonical reference table of all skills
  hero_skills              Instance of a catalog skill owned by a specific hero
  hero_skill_effects       Normalised effect rows attached to hero_skills

Combat / identity (retained from v1)
  hero_body_parts          Body-part HP / armor / status
  hero_combat_stats        Lifetime aggregate combat counters
  hero_titles              Earned achievement titles
  hero_resurrection_events Resurrection audit log
  hero_history             General event audit trail

Removed (v1 → v2)
  hero_abilities           → replaced by skills_catalog + hero_skills
  hero_training_queue      → removed (no training system)
  hero_perks               → removed (no perk-tree progression)
"""

from sqlalchemy import (
    Column, Integer, String, ForeignKey, UniqueConstraint,
    Boolean, DateTime, Index, Text, Float,
    Enum as SAEnum,
)
from sqlalchemy.orm import relationship
from app.database.base import Base, SoftDeleteMixin
from datetime import datetime
import enum


# ───────────────────────────────────────────────────────────────────
# Enums
# ───────────────────────────────────────────────────────────────────

class HeroRole(str, enum.Enum):
    """Five base hero roles."""
    VANGUARD   = "VANGUARD"
    STRIKER    = "STRIKER"
    CONTROLLER = "CONTROLLER"
    SUPPORT    = "SUPPORT"
    TRANSFER   = "TRANSFER"


class SkillFamily(str, enum.Enum):
    """Broad skill category."""
    COMBAT   = "COMBAT"
    BUFF     = "BUFF"
    DEBUFF   = "DEBUFF"
    TRANSFER = "TRANSFER"
    CONTROL  = "CONTROL"


class CastType(str, enum.Enum):
    """How a skill is activated."""
    INSTANT = "INSTANT"
    CAST    = "CAST"
    CHANNEL = "CHANNEL"
    AURA    = "AURA"
    TRIGGER = "TRIGGER"
    LINK    = "LINK"


class TargetType(str, enum.Enum):
    """Who can be targeted."""
    SELF   = "SELF"
    SINGLE = "SINGLE"
    AOE    = "AOE"
    TEAM   = "TEAM"
    ALL    = "ALL"


class TargetTeam(str, enum.Enum):
    """Which side a skill affects."""
    ALLY  = "ALLY"
    ENEMY = "ENEMY"
    ANY   = "ANY"


class SkillSourceType(str, enum.Enum):
    """How a hero acquired a skill instance."""
    GENERATION = "GENERATION"
    ABSORPTION = "ABSORPTION"
    EVENT      = "EVENT"
    ARTIFACT   = "ARTIFACT"


class HeroCondition(str, enum.Enum):
    """Overall hero health state."""
    HEALTHY          = "healthy"
    WOUNDED          = "wounded"
    SEVERELY_INJURED = "severely_injured"
    CRIPPLED         = "crippled"
    DEAD             = "dead"


class BodyPartStatus(str, enum.Enum):
    """Individual body-part damage state."""
    HEALTHY   = "healthy"
    INJURED   = "injured"
    CRIPPLED  = "crippled"
    BROKEN    = "broken"
    DESTROYED = "destroyed"


# ───────────────────────────────────────────────────────────────────
# 1. heroes
# ───────────────────────────────────────────────────────────────────

class Hero(SoftDeleteMixin, Base):
    __tablename__ = "heroes"

    id       = Column(Integer, primary_key=True, index=True)
    owner_id = Column(Integer, ForeignKey("users.id"), index=True, nullable=False)
    name     = Column(String(100), nullable=False)

    # ── Generation meta ──────────────────────────────────────────
    generation_seed = Column(
        String(64), nullable=True,
        comment="Hex seed used during hero generation",
    )
    generation_version = Column(
        Integer, nullable=False, default=1,
        comment="Algorithm version that created this hero",
    )
    hero_generation_level = Column(
        Integer, nullable=False, default=1,
        comment="Highest completed generation layer (1-10)",
    )

    # ── Roles ─────────────────────────────────────────────────────
    primary_role = Column(
        SAEnum(HeroRole, name="hero_role", create_constraint=True),
        nullable=False,
        comment="Determines base skill pool and stat curves",
    )
    secondary_role = Column(
        SAEnum(HeroRole, name="hero_role", create_constraint=False),
        nullable=True,
        comment="Optional hybrid role unlocked at higher gen layers",
    )

    # ── Core coefficients ─────────────────────────────────────────
    hero_coherence = Column(
        Float, nullable=False, default=1.0,
        comment="Internal consistency; affects skill synergy scaling",
    )
    stability = Column(
        Float, nullable=False, default=1.0,
        comment="Resistance to condition decay over time",
    )
    control_susceptibility = Column(
        Float, nullable=False, default=1.0,
        comment="Vulnerability to crowd-control effects (lower = more resistant)",
    )
    transfer_conductivity = Column(
        Float, nullable=False, default=1.0,
        comment="Efficiency of drain/transfer effects applied to this hero",
    )
    execution_resonance = Column(
        Float, nullable=False, default=1.0,
        comment="Bonus multiplier on kill-trigger effects",
    )
    affinity_bias = Column(
        Float, nullable=False, default=0.0,
        comment="Temperament axis -1.0 … +1.0",
    )

    # ── HP / condition ────────────────────────────────────────────
    current_hp = Column(Integer, nullable=False, default=100)
    max_hp_override = Column(
        Integer, nullable=True, default=None,
        comment="Manual cap; NULL → use derived from stats",
    )
    condition = Column(
        SAEnum(HeroCondition, name="hero_condition", create_constraint=True),
        nullable=False,
        default=HeroCondition.HEALTHY,
        comment="Overall hero health state",
    )
    resurrection_count = Column(
        Integer, nullable=False, default=0,
        comment="Times this hero has been revived",
    )

    # ── Death tracking ────────────────────────────────────────────
    is_dead     = Column(Boolean, default=False)
    dead_at     = Column(DateTime, nullable=True)
    death_cause = Column(
        String(200), nullable=True,
        comment="e.g. 'killed_by:hero:42', 'permadeath:arena'",
    )
    is_permadead = Column(
        Boolean, default=False,
        comment="True → hero cannot be revived",
    )

    # ── Kill / absorption counters ────────────────────────────────
    total_kills    = Column(Integer, nullable=False, default=0)
    total_deaths   = Column(Integer, nullable=False, default=0)
    total_absorbed = Column(
        Integer, nullable=False, default=0,
        comment="Times kill-absorb triggered",
    )

    # ── Auction flag ──────────────────────────────────────────────
    is_on_auction = Column(Boolean, default=False)

    # ── Meta ──────────────────────────────────────────────────────
    locale     = Column(String(5), nullable=False, default="en")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    updated_at = Column(
        DateTime, nullable=False,
        default=datetime.utcnow, onupdate=datetime.utcnow,
    )

    # ── Relationships ─────────────────────────────────────────────
    owner             = relationship("User", back_populates="heroes")
    equipment_items   = relationship("Equipment", back_populates="hero",
                                     cascade="all, delete-orphan")

    stats             = relationship("HeroStats", back_populates="hero",
                                     uselist=False, cascade="all, delete-orphan",
                                     lazy="joined")
    generation_layers = relationship("HeroGenerationLayer", back_populates="hero",
                                     cascade="all, delete-orphan", lazy="noload")
    tags              = relationship("HeroTag", back_populates="hero",
                                     cascade="all, delete-orphan", lazy="selectin")
    skills            = relationship("HeroSkill", back_populates="hero",
                                     cascade="all, delete-orphan", lazy="selectin")
    hidden_traits     = relationship("HeroHiddenTrait", back_populates="hero",
                                     cascade="all, delete-orphan", lazy="noload")

    body_parts          = relationship("HeroBodyPart", back_populates="hero",
                                       cascade="all, delete-orphan", lazy="selectin")
    combat_stats        = relationship("HeroCombatStats", back_populates="hero",
                                       uselist=False, cascade="all, delete-orphan",
                                       lazy="noload")
    titles              = relationship("HeroTitle", back_populates="hero",
                                       cascade="all, delete-orphan", lazy="selectin")
    resurrection_events = relationship("HeroResurrectionEvent",
                                       back_populates="hero",
                                       cascade="all, delete-orphan", lazy="noload")
    history_entries     = relationship("HeroHistory", back_populates="hero",
                                       cascade="all, delete-orphan", lazy="noload")

    __table_args__ = (
        Index("ix_heroes_owner_deleted", "owner_id", "is_deleted"),
        Index("ix_heroes_primary_role", "primary_role"),
    )


# ───────────────────────────────────────────────────────────────────
# 2. hero_stats
# ───────────────────────────────────────────────────────────────────

class HeroStats(Base):
    __tablename__ = "hero_stats"

    id       = Column(Integer, primary_key=True, index=True)
    hero_id  = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"),
                      nullable=False, unique=True, index=True)

    health    = Column(Integer, nullable=False, default=100)
    stamina   = Column(Integer, nullable=False, default=100)
    defense   = Column(Integer, nullable=False, default=10)
    vision    = Column(Integer, nullable=False, default=10)
    speed     = Column(Integer, nullable=False, default=10)
    agility   = Column(Integer, nullable=False, default=10)
    luck      = Column(Integer, nullable=False, default=5)
    willpower = Column(Integer, nullable=False, default=5)

    hero = relationship("Hero", back_populates="stats")


# ───────────────────────────────────────────────────────────────────
# 3. hero_generation_layers
# ───────────────────────────────────────────────────────────────────

class HeroGenerationLayer(Base):
    __tablename__ = "hero_generation_layers"

    id          = Column(Integer, primary_key=True, index=True)
    hero_id     = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"),
                         nullable=False, index=True)
    layer_index = Column(Integer, nullable=False,
                         comment="1-based generation layer (1..10)")
    success     = Column(Boolean, nullable=False)
    success_rate_used = Column(Float, nullable=False,
                               comment="The success probability applied at this layer")
    roll_value  = Column(Float, nullable=False,
                         comment="Raw RNG roll result (0.0..1.0)")
    payload_json = Column(Text, nullable=True,
                          comment="JSON blob with layer-specific generation data")

    hero = relationship("Hero", back_populates="generation_layers")

    __table_args__ = (
        UniqueConstraint("hero_id", "layer_index", name="uq_hero_gen_layer"),
        Index("ix_hero_gen_layers_hero", "hero_id"),
    )


# ───────────────────────────────────────────────────────────────────
# 4. hero_tags
# ───────────────────────────────────────────────────────────────────

class HeroTag(Base):
    __tablename__ = "hero_tags"

    id       = Column(Integer, primary_key=True, index=True)
    hero_id  = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"),
                      nullable=False, index=True)
    tag_code  = Column(String(60), nullable=False,
                       comment="Machine code, e.g. 'aggressive', 'tactical'")
    tag_group = Column(String(40), nullable=False,
                       comment="Category: 'personality', 'combat_style', 'affinity'")
    tag_value = Column(Float, nullable=True,
                       comment="Optional numeric weight / magnitude")

    hero = relationship("Hero", back_populates="tags")

    __table_args__ = (
        UniqueConstraint("hero_id", "tag_code", name="uq_hero_tag"),
        Index("ix_hero_tags_hero_group", "hero_id", "tag_group"),
    )


# ───────────────────────────────────────────────────────────────────
# 5. skills_catalog  (reference table — NOT per-hero)
# ───────────────────────────────────────────────────────────────────

class SkillsCatalog(Base):
    __tablename__ = "skills_catalog"

    id           = Column(Integer, primary_key=True, index=True)
    skill_code   = Column(String(80), nullable=False, unique=True, index=True,
                          comment="Canonical machine key, e.g. 'shield_bash'")
    display_name = Column(String(120), nullable=False)
    skill_family = Column(
        SAEnum(SkillFamily, name="skill_family", create_constraint=True),
        nullable=False,
    )
    description_short = Column(String(255), nullable=True)
    description_full  = Column(Text, nullable=True)

    target_type = Column(
        SAEnum(TargetType, name="target_type", create_constraint=True),
        nullable=False,
    )
    target_team = Column(
        SAEnum(TargetTeam, name="target_team", create_constraint=True),
        nullable=False,
    )
    cast_type = Column(
        SAEnum(CastType, name="cast_type", create_constraint=True),
        nullable=False,
    )

    stamina_cost_base = Column(Integer, nullable=False, default=0)
    cooldown_base     = Column(Float, nullable=False, default=0.0)
    duration_base     = Column(Float, nullable=False, default=0.0)
    power_base        = Column(Integer, nullable=False, default=0)
    radius_base       = Column(Float, nullable=False, default=0.0)

    requires_vision   = Column(Boolean, nullable=False, default=True)
    is_redirectable   = Column(Boolean, nullable=False, default=False)
    is_interruptible  = Column(Boolean, nullable=False, default=True)
    is_stealable      = Column(Boolean, nullable=False, default=False)
    is_upgradable     = Column(Boolean, nullable=False, default=True)
    has_kill_trigger   = Column(Boolean, nullable=False, default=False)

    control_tier   = Column(Integer, nullable=True,
                            comment="CC tier 1-5; NULL if not a control skill")
    metadata_json  = Column(Text, nullable=True,
                            comment="Extra JSON config for special skill behaviour")


# ───────────────────────────────────────────────────────────────────
# 6. hero_skills
# ───────────────────────────────────────────────────────────────────

class HeroSkill(Base):
    __tablename__ = "hero_skills"

    id       = Column(Integer, primary_key=True, index=True)
    hero_id  = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"),
                      nullable=False, index=True)
    skill_code = Column(
        String(80),
        ForeignKey("skills_catalog.skill_code", ondelete="CASCADE"),
        nullable=False, index=True,
    )

    generation_level      = Column(Integer, nullable=False, default=1,
                                   comment="Gen layer that granted this skill")
    cost_generation_level = Column(Integer, nullable=False, default=1,
                                   comment="Gen layer that set cost params")
    power_value        = Column(Integer, nullable=False, default=0)
    duration_value     = Column(Float, nullable=False, default=0.0)
    cooldown_value     = Column(Float, nullable=False, default=0.0)
    stamina_cost_value = Column(Integer, nullable=False, default=0)
    radius_value       = Column(Float, nullable=False, default=0.0)
    upgrade_count      = Column(Integer, nullable=False, default=0)

    source_type = Column(
        SAEnum(SkillSourceType, name="skill_source_type", create_constraint=True),
        nullable=False,
        default=SkillSourceType.GENERATION,
    )
    slot_index   = Column(Integer, nullable=False, default=0,
                          comment="Skill bar slot (0-based)")
    is_signature = Column(Boolean, nullable=False, default=False,
                          comment="True → hero's defining skill")
    payload_json = Column(Text, nullable=True,
                          comment="JSON blob for instance-specific overrides")

    hero          = relationship("Hero", back_populates="skills")
    catalog_entry = relationship("SkillsCatalog", lazy="joined")
    effects       = relationship("HeroSkillEffect", back_populates="hero_skill",
                                 cascade="all, delete-orphan", lazy="selectin")

    __table_args__ = (
        UniqueConstraint("hero_id", "slot_index", name="uq_hero_skill_slot"),
        Index("ix_hero_skills_hero", "hero_id"),
    )


# ───────────────────────────────────────────────────────────────────
# 7. hero_skill_effects
# ───────────────────────────────────────────────────────────────────

class HeroSkillEffect(Base):
    __tablename__ = "hero_skill_effects"

    id            = Column(Integer, primary_key=True, index=True)
    hero_skill_id = Column(Integer,
                           ForeignKey("hero_skills.id", ondelete="CASCADE"),
                           nullable=False, index=True)
    effect_type   = Column(String(60), nullable=False,
                           comment="e.g. 'damage', 'heal', 'stun', 'dot', 'buff', 'drain'")
    effect_target = Column(String(60), nullable=False,
                           comment="e.g. 'health', 'stamina', 'defense', 'speed'")
    effect_value  = Column(Float, nullable=False, default=0.0)
    effect_scaling_json = Column(Text, nullable=True,
                                 comment="JSON: scaling rules, stat weights, etc.")

    hero_skill = relationship("HeroSkill", back_populates="effects")


# ───────────────────────────────────────────────────────────────────
# 8. hero_hidden_traits
# ───────────────────────────────────────────────────────────────────

class HeroHiddenTrait(Base):
    __tablename__ = "hero_hidden_traits"

    id         = Column(Integer, primary_key=True, index=True)
    hero_id    = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    trait_code = Column(String(60), nullable=False,
                        comment="Machine key, e.g. 'crit_affinity', 'pain_threshold'")
    trait_value = Column(Float, nullable=False, default=0.0)

    hero = relationship("Hero", back_populates="hidden_traits")

    __table_args__ = (
        UniqueConstraint("hero_id", "trait_code", name="uq_hero_hidden_trait"),
        Index("ix_hero_hidden_traits_hero", "hero_id"),
    )


# ───────────────────────────────────────────────────────────────────
# Retained from v1: Hero Body Parts
# ───────────────────────────────────────────────────────────────────

class HeroBodyPart(Base):
    __tablename__ = "hero_body_parts"

    id        = Column(Integer, primary_key=True, index=True)
    hero_id   = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"),
                       nullable=False, index=True)
    part_name = Column(String(20), nullable=False,
                       comment="head, torso, left_arm, right_arm, left_leg, right_leg")
    max_hp     = Column(Integer, nullable=False)
    current_hp = Column(Integer, nullable=False)
    armor      = Column(Integer, nullable=False, default=0)
    status = Column(
        SAEnum(BodyPartStatus, name="body_part_status", create_constraint=True),
        nullable=False,
        default=BodyPartStatus.HEALTHY,
    )
    updated_at = Column(DateTime, nullable=False,
                        default=datetime.utcnow, onupdate=datetime.utcnow)

    hero = relationship("Hero", back_populates="body_parts")

    __table_args__ = (
        UniqueConstraint("hero_id", "part_name", name="uq_hero_body_part"),
        Index("ix_hero_body_parts_hero", "hero_id"),
    )


# ───────────────────────────────────────────────────────────────────
# Retained from v1: Hero Combat Stats
# ───────────────────────────────────────────────────────────────────

class HeroCombatStats(Base):
    __tablename__ = "hero_combat_stats"

    id      = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"),
                     nullable=False, unique=True, index=True)

    total_kills    = Column(Integer, nullable=False, default=0)
    boss_kills     = Column(Integer, nullable=False, default=0)
    arena_wins     = Column(Integer, nullable=False, default=0)
    battles        = Column(Integer, nullable=False, default=0)
    damage_dealt   = Column(Integer, nullable=False, default=0)
    damage_taken   = Column(Integer, nullable=False, default=0)
    last_battle_at = Column(DateTime, nullable=True)

    hero = relationship("Hero", back_populates="combat_stats")


# ───────────────────────────────────────────────────────────────────
# Retained from v1: Hero Titles
# ───────────────────────────────────────────────────────────────────

class HeroTitle(Base):
    __tablename__ = "hero_titles"

    id         = Column(Integer, primary_key=True, index=True)
    hero_id    = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    title_code = Column(String(60), nullable=False,
                        comment="Machine key, e.g. 'the_slayer'")
    title_name = Column(String(120), nullable=False,
                        comment="Display name, e.g. 'The Slayer'")
    awarded_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    source     = Column(String(120), nullable=True,
                        comment="How earned: 'kills:100', 'arena_wins:50', etc.")

    hero = relationship("Hero", back_populates="titles")

    __table_args__ = (
        UniqueConstraint("hero_id", "title_code", name="uq_hero_title"),
        Index("ix_hero_titles_hero", "hero_id"),
    )


# ───────────────────────────────────────────────────────────────────
# Retained from v1: Hero Resurrection Events
# ───────────────────────────────────────────────────────────────────

class HeroResurrectionEvent(Base):
    __tablename__ = "hero_resurrection_events"

    id            = Column(Integer, primary_key=True, index=True)
    hero_id       = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"),
                           nullable=False, index=True)
    artifact_used = Column(String(120), nullable=False,
                           comment="e.g. 'phoenix_core', 'heart_of_reversal'")
    revived_at    = Column(DateTime, nullable=False, default=datetime.utcnow)
    side_effects_json = Column(Text, nullable=True,
                               comment="JSON array of side effects applied")
    condition_before = Column(
        SAEnum(HeroCondition, name="hero_condition", create_constraint=False),
        nullable=False,
        default=HeroCondition.DEAD,
    )
    condition_after = Column(
        SAEnum(HeroCondition, name="hero_condition", create_constraint=False),
        nullable=False,
        default=HeroCondition.WOUNDED,
    )
    hp_restored_to = Column(Integer, nullable=False, default=0)

    hero = relationship("Hero", back_populates="resurrection_events")

    __table_args__ = (
        Index("ix_resurrection_hero", "hero_id"),
    )


# ───────────────────────────────────────────────────────────────────
# Retained from v1: Hero History (audit trail)
# ───────────────────────────────────────────────────────────────────

class HeroHistory(Base):
    __tablename__ = "hero_history"

    id         = Column(Integer, primary_key=True, index=True)
    hero_id    = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"),
                        nullable=False, index=True)
    event_type = Column(String(50), nullable=False,
                        comment="e.g. 'created','skill_gained','killed','absorbed'")
    event_data = Column(Text, nullable=True,
                        comment="JSON payload with event details")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    hero = relationship("Hero", back_populates="history_entries")

    __table_args__ = (
        Index("ix_hero_history_hero_event", "hero_id", "event_type"),
    )