from sqlalchemy import Column, Integer, String, ForeignKey, UniqueConstraint, Boolean, DateTime, Numeric, CheckConstraint, Index, Text, Float, Enum as SAEnum
from sqlalchemy.orm import relationship
from app.database.base import Base, SoftDeleteMixin
from datetime import datetime
from decimal import Decimal
import enum


# ---------------------------------------------------------------------------
# Enums
# ---------------------------------------------------------------------------

class HeroArchetype(str, enum.Enum):
    VANGUARD = "VANGUARD"
    PREDATOR = "PREDATOR"
    PHANTOM = "PHANTOM"
    MYSTIC = "MYSTIC"
    WARDEN = "WARDEN"
    APOSTLE = "APOSTLE"
    CHIMERA = "CHIMERA"


class AbilityType(str, enum.Enum):
    OFFENSIVE = "OFFENSIVE"
    DEFENSIVE = "DEFENSIVE"
    UTILITY = "UTILITY"
    SUPPORT = "SUPPORT"
    MUTATION = "MUTATION"


class AbilityDomain(str, enum.Enum):
    BIOMORPH = "BIOMORPH"
    SPACE = "SPACE"
    PSIONIC = "PSIONIC"
    ELEMENTAL = "ELEMENTAL"
    SHADOW = "SHADOW"
    BLOOD = "BLOOD"
    ORDER = "ORDER"
    CHAOS = "CHAOS"


class BodyPartStatus(str, enum.Enum):
    HEALTHY = "healthy"
    INJURED = "injured"
    CRIPPLED = "crippled"
    BROKEN = "broken"
    DESTROYED = "destroyed"


class TrainingType(str, enum.Enum):
    ATTRIBUTE = "attribute"
    DISCIPLINE = "discipline"
    ABILITY = "ability"


class TrainingStatus(str, enum.Enum):
    QUEUED = "queued"
    RUNNING = "running"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class HeroCondition(str, enum.Enum):
    HEALTHY = "healthy"
    WOUNDED = "wounded"
    SEVERELY_INJURED = "severely_injured"
    CRIPPLED = "crippled"
    DEAD = "dead"


# ---------------------------------------------------------------------------
# Hero Model
# ---------------------------------------------------------------------------

class Hero(SoftDeleteMixin, Base):
    __tablename__ = "heroes"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    generation = Column(Integer, nullable=False, default=1)
    nickname = Column(String(100), nullable=False, default="")

    # --- PRIMARY STATS (S.P.E.I.A.L.W) ---
    strength = Column(Integer, nullable=False, default=0)
    perception = Column(Integer, nullable=False, default=0)
    endurance = Column(Integer, nullable=False, default=0)
    intelligence = Column(Integer, nullable=False, default=0)
    agility = Column(Integer, nullable=False, default=0)
    luck = Column(Integer, nullable=False, default=0)
    willpower = Column(Integer, nullable=False, default=0)

    # --- DEPRECATED COLUMNS (kept for migration, will be dropped) ---
    # speed, health, defense, field_of_view are now derived stats.
    # These columns remain temporarily so Alembic can generate a clean
    # data-migration step.  After migration they should be dropped.
    speed = Column(Integer, nullable=True, default=None)
    health = Column(Integer, nullable=True, default=None)
    defense = Column(Integer, nullable=True, default=None)
    field_of_view = Column(Integer, nullable=True, default=None)

    # --- ARCHETYPE ---
    archetype = Column(
        SAEnum(HeroArchetype, name="hero_archetype", create_constraint=True),
        nullable=True,
        default=None,
        comment="Hero archetype determines growth curves and ability pool",
    )

    # --- BODY / HP STATE ---
    current_hp = Column(Integer, nullable=False, default=100)
    max_hp_override = Column(Integer, nullable=True, default=None, comment="Manual cap; NULL = use derived")
    condition = Column(
        SAEnum(HeroCondition, name="hero_condition", create_constraint=True),
        nullable=False,
        default=HeroCondition.HEALTHY,
        comment="Overall hero health state: healthy → wounded → severely_injured → crippled → dead",
    )
    resurrection_count = Column(Integer, nullable=False, default=0, comment="Times this hero has been revived")

    # --- PERMANENT DEATH ---
    is_dead = Column(Boolean, default=False)
    dead_at = Column(DateTime, nullable=True)
    death_cause = Column(String(200), nullable=True, comment="e.g. 'killed_by:hero:42', 'permadeath:arena'")
    is_permadead = Column(Boolean, default=False, comment="True = cannot be revived")

    # --- KILL / ABSORPTION TRACKING ---
    total_kills = Column(Integer, nullable=False, default=0)
    total_deaths = Column(Integer, nullable=False, default=0)
    total_absorbed = Column(Integer, nullable=False, default=0, comment="Times Predatory Assimilation triggered")

    # --- ECONOMY ---
    gold = Column(Numeric(12, 2), default=Decimal('0.00'))
    level = Column(Integer, nullable=False, default=1)
    experience = Column(Integer, nullable=False, default=0)

    # --- TRAINING ---
    is_training = Column(Boolean, default=False)
    training_end_time = Column(DateTime, nullable=True)
    training_stat = Column(String(30), nullable=True, comment="Which primary stat is being trained")
    training_sessions_completed = Column(Integer, nullable=False, default=0)

    # --- META ---
    locale = Column(String(5), nullable=False, default="en")
    owner_id = Column(Integer, ForeignKey("users.id"), index=True)
    is_on_auction = Column(Boolean, default=False)
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    # --- RELATIONSHIPS ---
    owner = relationship("User", back_populates="heroes")
    perks = relationship("HeroPerk", back_populates="hero", cascade="all, delete-orphan")
    equipment_items = relationship("Equipment", back_populates="hero", cascade="all, delete-orphan")
    abilities = relationship("HeroAbility", back_populates="hero", cascade="all, delete-orphan", lazy="selectin")
    history_entries = relationship("HeroHistory", back_populates="hero", cascade="all, delete-orphan", lazy="noload")
    body_parts = relationship("HeroBodyPart", back_populates="hero", cascade="all, delete-orphan", lazy="selectin")
    training_queue = relationship("HeroTrainingQueue", back_populates="hero", cascade="all, delete-orphan", lazy="noload")
    combat_stats = relationship("HeroCombatStats", back_populates="hero", uselist=False, cascade="all, delete-orphan", lazy="selectin")
    titles = relationship("HeroTitle", back_populates="hero", cascade="all, delete-orphan", lazy="selectin")
    resurrection_events = relationship("HeroResurrectionEvent", back_populates="hero", cascade="all, delete-orphan", lazy="noload")

    __table_args__ = (
        CheckConstraint('gold >= 0', name='ck_hero_gold_non_negative'),
        Index('ix_heroes_owner_deleted', 'owner_id', 'is_deleted'),
        Index('ix_heroes_archetype', 'archetype'),
    )


# ---------------------------------------------------------------------------
# Hero Ability Model
# ---------------------------------------------------------------------------

class HeroAbility(Base):
    __tablename__ = "hero_abilities"

    id = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"), nullable=False, index=True)

    ability_code = Column(String(80), nullable=False, comment="Unique machine code, e.g. 'predatory_assimilation'")
    ability_name = Column(String(120), nullable=False, comment="Display name")
    ability_type = Column(
        SAEnum(AbilityType, name="ability_type", create_constraint=True),
        nullable=False,
    )
    ability_domain = Column(
        SAEnum(AbilityDomain, name="ability_domain", create_constraint=True),
        nullable=False,
    )
    ability_level = Column(Integer, nullable=False, default=1)
    is_active = Column(Boolean, nullable=False, default=True)
    metadata_json = Column(Text, nullable=True, comment="JSON blob for ability-specific data")
    acquired_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    source = Column(String(80), nullable=True, comment="How ability was acquired: 'generation', 'absorption', 'training', 'event'")

    hero = relationship("Hero", back_populates="abilities")

    __table_args__ = (
        UniqueConstraint('hero_id', 'ability_code', name='uq_hero_ability_code'),
        Index('ix_hero_abilities_type', 'hero_id', 'ability_type'),
    )


# ---------------------------------------------------------------------------
# Hero History Model (audit trail)
# ---------------------------------------------------------------------------

class HeroHistory(Base):
    __tablename__ = "hero_history"

    id = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"), nullable=False, index=True)
    event_type = Column(String(50), nullable=False, comment="e.g. 'created','leveled_up','killed','absorbed','trained','ability_gained'")
    event_data = Column(Text, nullable=True, comment="JSON payload with event details")
    created_at = Column(DateTime, nullable=False, default=datetime.utcnow)

    hero = relationship("Hero", back_populates="history_entries")

    __table_args__ = (
        Index('ix_hero_history_hero_event', 'hero_id', 'event_type'),
    )


# ---------------------------------------------------------------------------
# Hero Body Part Model
# ---------------------------------------------------------------------------

class HeroBodyPart(Base):
    __tablename__ = "hero_body_parts"

    id = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"), nullable=False, index=True)
    part_name = Column(String(20), nullable=False, comment="head, torso, left_arm, right_arm, left_leg, right_leg")
    max_hp = Column(Integer, nullable=False)
    current_hp = Column(Integer, nullable=False)
    armor = Column(Integer, nullable=False, default=0)
    status = Column(
        SAEnum(BodyPartStatus, name="body_part_status", create_constraint=True),
        nullable=False,
        default=BodyPartStatus.HEALTHY,
    )
    updated_at = Column(DateTime, nullable=False, default=datetime.utcnow, onupdate=datetime.utcnow)

    hero = relationship("Hero", back_populates="body_parts")

    __table_args__ = (
        UniqueConstraint('hero_id', 'part_name', name='uq_hero_body_part'),
        Index('ix_hero_body_parts_hero', 'hero_id'),
    )


# ---------------------------------------------------------------------------
# Hero Training Queue
# ---------------------------------------------------------------------------

class HeroTrainingQueue(Base):
    __tablename__ = "hero_training_queue"

    id = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"), nullable=False, index=True)

    training_type = Column(
        SAEnum(TrainingType, name="training_type", create_constraint=True),
        nullable=False,
        comment="attribute | discipline | ability",
    )
    training_target = Column(
        String(80), nullable=False,
        comment="What is being trained: stat name, discipline code, or ability code",
    )
    current_level = Column(Integer, nullable=False, default=0)
    target_level = Column(Integer, nullable=False, default=1)
    started_at = Column(DateTime, nullable=True)
    ends_at = Column(DateTime, nullable=True)
    status = Column(
        SAEnum(TrainingStatus, name="training_status", create_constraint=True),
        nullable=False,
        default=TrainingStatus.QUEUED,
    )
    room_slot = Column(Integer, nullable=False, default=0, comment="Training room slot index (0-based)")
    efficiency = Column(Float, nullable=False, default=1.0, comment="Multiplier (1.0 = normal speed)")

    hero = relationship("Hero", back_populates="training_queue")

    __table_args__ = (
        Index('ix_training_queue_hero_status', 'hero_id', 'status'),
    )


# ---------------------------------------------------------------------------
# Hero Combat Stats (aggregate lifetime counters)
# ---------------------------------------------------------------------------

class HeroCombatStats(Base):
    __tablename__ = "hero_combat_stats"

    id = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)

    total_kills = Column(Integer, nullable=False, default=0)
    boss_kills = Column(Integer, nullable=False, default=0)
    arena_wins = Column(Integer, nullable=False, default=0)
    battles = Column(Integer, nullable=False, default=0)
    damage_dealt = Column(Integer, nullable=False, default=0)
    damage_taken = Column(Integer, nullable=False, default=0)
    last_battle_at = Column(DateTime, nullable=True)

    hero = relationship("Hero", back_populates="combat_stats")


# ---------------------------------------------------------------------------
# Hero Titles
# ---------------------------------------------------------------------------

class HeroTitle(Base):
    __tablename__ = "hero_titles"

    id = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"), nullable=False, index=True)
    title_code = Column(String(60), nullable=False, comment="Machine key, e.g. 'the_slayer'")
    title_name = Column(String(120), nullable=False, comment="Display name, e.g. 'The Slayer'")
    awarded_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    source = Column(String(120), nullable=True, comment="How it was earned: 'kills:100', 'arena_wins:50', etc.")

    hero = relationship("Hero", back_populates="titles")

    __table_args__ = (
        UniqueConstraint('hero_id', 'title_code', name='uq_hero_title'),
        Index('ix_hero_titles_hero', 'hero_id'),
    )


# ---------------------------------------------------------------------------
# Hero Resurrection Events
# ---------------------------------------------------------------------------

class HeroResurrectionEvent(Base):
    __tablename__ = "hero_resurrection_events"

    id = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"), nullable=False, index=True)
    artifact_used = Column(String(120), nullable=False, comment="e.g. 'phoenix_core', 'heart_of_reversal'")
    revived_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    side_effects_json = Column(Text, nullable=True, comment="JSON array of side effects applied")
    condition_before = Column(
        SAEnum(HeroCondition, name="hero_condition", create_constraint=False),
        nullable=False,
        default=HeroCondition.DEAD,
        comment="Hero condition at time of resurrection (should be dead)",
    )
    condition_after = Column(
        SAEnum(HeroCondition, name="hero_condition", create_constraint=False),
        nullable=False,
        default=HeroCondition.WOUNDED,
        comment="Resulting condition after revival",
    )
    hp_restored_to = Column(Integer, nullable=False, default=0, comment="HP hero was restored to")

    hero = relationship("Hero", back_populates="resurrection_events")

    __table_args__ = (
        Index('ix_resurrection_hero', 'hero_id'),
    )


# ---------------------------------------------------------------------------
# Hero Perk (unchanged)
# ---------------------------------------------------------------------------

class HeroPerk(Base):
    __tablename__ = "hero_perks"
    id = Column(Integer, primary_key=True)
    hero_id = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"))
    perk_id = Column(Integer, ForeignKey("perks.id"), nullable=True)
    perk_name = Column(String, nullable=True)
    perk_level = Column(Integer, nullable=False)
    hero = relationship("app.database.models.hero.Hero", back_populates="perks")
    perk = relationship("Perk")
    __table_args__ = (UniqueConstraint('hero_id', 'perk_id', name='_hero_perk_uc'),) 