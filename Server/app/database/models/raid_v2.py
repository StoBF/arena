"""
Raid Boss System v2 — DB Models
================================
14 entities covering the full design document:
  RaidBossTemplate, RaidBossSpawn, RaidBossProgress, RaidBossMutation,
  RaidBossPhase, RaidDropTable, RaidDropEntry,
  RaidRoom, RaidParticipant,
  RaidCoalition, RaidCoalitionClan,
  RaidAccessScore, RaidBattleLog, RaidContribution
"""
from __future__ import annotations

import enum
from datetime import datetime
from typing import Optional

from sqlalchemy import (
    Boolean, Column, DateTime, Enum, Float,
    ForeignKey, Integer, JSON, String, Text, UniqueConstraint,
)
from sqlalchemy.orm import relationship

from app.database.models.models import Base


# ── Enums ────────────────────────────────────────────────────────────────────

class BossCategory(str, enum.Enum):
    hourly   = "hourly"       # every hour, 15-min window
    half_day = "half_day"     # every 12h, 30-min window
    weekly   = "weekly"       # 1-2×/week, qualification required
    monthly  = "monthly"      # 1×/month, seasonal final boss


class BossArchetype(str, enum.Enum):
    tank        = "tank"
    hunter      = "hunter"
    mage        = "mage"
    parasite    = "parasite"
    swarm       = "swarm"
    judge       = "judge"
    apex        = "apex"


class SpawnStatus(str, enum.Enum):
    pending   = "pending"
    open      = "open"          # active window, accepting raids
    locked    = "locked"        # fight in progress
    defeated  = "defeated"
    expired   = "expired"       # window closed, nobody fought


class RoomStatus(str, enum.Enum):
    preparing = "preparing"
    locked    = "locked"        # roster locked, waiting for start
    fighting  = "fighting"
    completed = "completed"
    cancelled = "cancelled"


class DropOwnership(str, enum.Enum):
    personal   = "personal"
    clan       = "clan"
    coalition  = "coalition"
    weighted   = "weighted"     # unique item: weighted roll among contributors


class DropRarity(str, enum.Enum):
    common     = "common"
    uncommon   = "uncommon"
    rare       = "rare"
    epic       = "epic"
    legendary  = "legendary"
    mythic     = "mythic"


class MutationTrigger(str, enum.Enum):
    level_up    = "level_up"
    win_streak  = "win_streak"
    rank_up     = "rank_up"
    manual      = "manual"


class CoalitionStatus(str, enum.Enum):
    forming   = "forming"
    ready     = "ready"
    disbanded = "disbanded"


# ── 1. RaidBossTemplate ───────────────────────────────────────────────────────
class RaidBossTemplate(Base):
    """
    Static definition of one of the 9 raid bosses.
    Seeded once; never changes unless patched.
    """
    __tablename__ = "raid_boss_templates"

    id           = Column(Integer, primary_key=True)
    code         = Column(String(64), unique=True, nullable=False)   # e.g. "stone_colossus"
    name         = Column(String(128), nullable=False)
    category     = Column(Enum(BossCategory), nullable=False)
    archetype    = Column(Enum(BossArchetype), nullable=False)

    # Limits
    max_clans    = Column(Integer, nullable=False, default=1)
    max_heroes   = Column(Integer, nullable=False, default=5)
    num_phases   = Column(Integer, nullable=False, default=2)

    # Base stats (used by battle service)
    base_level   = Column(Integer, nullable=False, default=1)
    base_hp      = Column(Integer, nullable=False, default=10000)
    base_armor   = Column(Float,   nullable=False, default=0.0)
    base_damage  = Column(Integer, nullable=False, default=500)
    base_speed   = Column(Float,   nullable=False, default=1.0)
    base_xp      = Column(Integer, nullable=False, default=1000)   # XP boss earns from winning

    # Spawn schedule (stored as JSON for flexibility)
    # {"interval_hours": 1, "window_minutes": 15}
    spawn_config = Column(JSON, nullable=False, default=dict)

    # Whether access qualification is required
    requires_qualification = Column(Boolean, nullable=False, default=False)
    # Minimum RAP (Raid Access Points) clan must have to enter (0 = unrestricted)
    min_access_points = Column(Integer, nullable=False, default=0)

    description  = Column(Text, nullable=True)
    lore         = Column(Text, nullable=True)

    # --- relationships ---
    spawns       = relationship("RaidBossSpawn",    back_populates="template", lazy="select")
    progress     = relationship("RaidBossProgress", back_populates="template", uselist=False)
    phases       = relationship("RaidBossPhase",    back_populates="template", order_by="RaidBossPhase.phase_number")
    drop_table   = relationship("RaidDropEntry",    back_populates="template")


# ── 2. RaidBossSpawn ──────────────────────────────────────────────────────────
class RaidBossSpawn(Base):
    """
    A concrete timed appearance of a boss. Created by the scheduler.
    """
    __tablename__ = "raid_boss_spawns"

    id            = Column(Integer, primary_key=True)
    template_id   = Column(Integer, ForeignKey("raid_boss_templates.id"), nullable=False)
    status        = Column(Enum(SpawnStatus), nullable=False, default=SpawnStatus.pending)

    opens_at      = Column(DateTime, nullable=False)
    closes_at     = Column(DateTime, nullable=False)
    started_at    = Column(DateTime, nullable=True)
    resolved_at   = Column(DateTime, nullable=True)

    # snapshot of boss level at spawn time (from RaidBossProgress)
    boss_level_snapshot = Column(Integer, nullable=False, default=1)
    win_streak_snapshot = Column(Integer, nullable=False, default=0)

    # result
    defeated_by_room_id = Column(Integer, ForeignKey("raid_rooms.id"), nullable=True)

    template = relationship("RaidBossTemplate", back_populates="spawns")
    room     = relationship("RaidRoom", foreign_keys=[defeated_by_room_id], uselist=False)


# ── 3. RaidBossProgress ───────────────────────────────────────────────────────
class RaidBossProgress(Base):
    """
    Boss progression state — updated after every fight outcome.
    """
    __tablename__ = "raid_boss_progress"

    id              = Column(Integer, primary_key=True)
    template_id     = Column(Integer, ForeignKey("raid_boss_templates.id"), unique=True, nullable=False)

    current_level   = Column(Integer, nullable=False, default=1)
    current_xp      = Column(Integer, nullable=False, default=0)
    xp_to_next      = Column(Integer, nullable=False, default=5000)
    rank            = Column(Integer, nullable=False, default=0)    # 0=normal, 1=elite, 2=legendary
    evolution_stage = Column(Integer, nullable=False, default=0)

    win_streak      = Column(Integer, nullable=False, default=0)
    total_wins      = Column(Integer, nullable=False, default=0)
    total_defeats   = Column(Integer, nullable=False, default=0)
    hero_kills      = Column(Integer, nullable=False, default=0)

    # Adaptive memory: resistances learned from past battles
    # {"physical": 0.0, "fire": 0.05, "poison": 0.10, ...}
    learned_resistances = Column(JSON, nullable=False, default=dict)
    # Patterns learned: {"anti_aoe": 0.3, "anti_heal": 0.2, ...}
    behavior_patterns   = Column(JSON, nullable=False, default=dict)

    updated_at      = Column(DateTime, nullable=False, default=datetime.utcnow)

    template  = relationship("RaidBossTemplate", back_populates="progress")
    mutations = relationship("RaidBossMutation", back_populates="progress")


# ── 4. RaidBossMutation ───────────────────────────────────────────────────────
class RaidBossMutation(Base):
    """
    Active mutation on a boss — temporary or permanent modifier.
    """
    __tablename__ = "raid_boss_mutations"

    id          = Column(Integer, primary_key=True)
    progress_id = Column(Integer, ForeignKey("raid_boss_progress.id"), nullable=False)

    code        = Column(String(64), nullable=False)    # e.g. "flesh_regen"
    name        = Column(String(128), nullable=False)
    description = Column(Text, nullable=True)
    trigger     = Column(Enum(MutationTrigger), nullable=False)

    # Effect JSON: {"type": "damage_resist", "element": "fire", "value": 0.15}
    effect      = Column(JSON, nullable=False, default=dict)

    is_active   = Column(Boolean, nullable=False, default=True)
    granted_at  = Column(DateTime, nullable=False, default=datetime.utcnow)
    expires_at  = Column(DateTime, nullable=True)   # None = permanent

    progress = relationship("RaidBossProgress", back_populates="mutations")


# ── 5. RaidBossPhase ──────────────────────────────────────────────────────────
class RaidBossPhase(Base):
    """
    Phase definition for a boss — static, seeded from catalog.
    """
    __tablename__ = "raid_boss_phases"

    id            = Column(Integer, primary_key=True)
    template_id   = Column(Integer, ForeignKey("raid_boss_templates.id"), nullable=False)
    phase_number  = Column(Integer, nullable=False)   # 1-indexed
    trigger_hp_pct = Column(Float,  nullable=False)   # phase starts when boss HP <= this %
    name          = Column(String(128), nullable=False)
    description   = Column(Text, nullable=True)

    # Modifiers JSON: {"damage_mult": 1.5, "speed_mult": 1.2, "summon_minions": true}
    modifiers     = Column(JSON, nullable=False, default=dict)
    # Special abilities unlocked in this phase
    abilities     = Column(JSON, nullable=False, default=list)
    # Arena changes: {"aoe_zones": true, "arena_shrink": false}
    arena_changes = Column(JSON, nullable=False, default=dict)

    template = relationship("RaidBossTemplate", back_populates="phases")

    __table_args__ = (
        UniqueConstraint("template_id", "phase_number", name="uq_boss_phase"),
    )


# ── 6. RaidDropEntry ──────────────────────────────────────────────────────────
class RaidDropEntry(Base):
    """
    One item/recipe in the boss's loot table.
    """
    __tablename__ = "raid_drop_entries"

    id            = Column(Integer, primary_key=True)
    template_id   = Column(Integer, ForeignKey("raid_boss_templates.id"), nullable=False)

    # What drops — exactly one of these is set
    item_code     = Column(String(64), nullable=True)    # resource / item code
    recipe_code   = Column(String(64), nullable=True)    # recipe code
    artifact_code = Column(String(64), nullable=True)    # artifact code

    display_name  = Column(String(128), nullable=False)
    rarity        = Column(Enum(DropRarity), nullable=False, default=DropRarity.common)
    ownership     = Column(Enum(DropOwnership), nullable=False, default=DropOwnership.personal)
    drop_group    = Column(String(64), nullable=True)   # "core", "recipe", "ultra_rare"

    base_chance   = Column(Float, nullable=False)        # 0.0–1.0
    min_qty       = Column(Integer, nullable=False, default=1)
    max_qty       = Column(Integer, nullable=False, default=1)

    # Conditions that boost chance:
    # [{"condition": "boss_level_gte", "value": 10, "bonus": 0.007}, ...]
    bonus_conditions = Column(JSON, nullable=False, default=list)

    is_guaranteed = Column(Boolean, nullable=False, default=False)   # always drops on win

    template = relationship("RaidBossTemplate", back_populates="drop_table")


# ── 7. RaidRoom ───────────────────────────────────────────────────────────────
class RaidRoom(Base):
    """
    Preparation room before a raid fight.
    """
    __tablename__ = "raid_rooms"

    id            = Column(Integer, primary_key=True)
    spawn_id      = Column(Integer, ForeignKey("raid_boss_spawns.id"), nullable=False)
    coalition_id  = Column(Integer, ForeignKey("raid_coalitions.id"), nullable=True)

    creator_user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    creator_clan_id = Column(Integer, ForeignKey("clans.id"), nullable=True)

    status        = Column(Enum(RoomStatus), nullable=False, default=RoomStatus.preparing)
    loot_rule     = Column(String(32), nullable=False, default="contribution")
    # contribution | equal | clan_share | weighted_roll

    created_at    = Column(DateTime, nullable=False, default=datetime.utcnow)
    locked_at     = Column(DateTime, nullable=True)
    started_at    = Column(DateTime, nullable=True)
    finished_at   = Column(DateTime, nullable=True)

    # Battle result
    outcome       = Column(String(32), nullable=True)   # "victory" | "defeat"
    total_ticks   = Column(Integer, nullable=True)

    participants  = relationship("RaidParticipant", back_populates="room", cascade="all, delete-orphan")
    contributions = relationship("RaidContribution", back_populates="room", cascade="all, delete-orphan")
    battle_log    = relationship("RaidBattleLog", back_populates="room", uselist=False)


# ── 8. RaidParticipant ────────────────────────────────────────────────────────
class RaidParticipant(Base):
    """
    One hero slot in a raid room.
    """
    __tablename__ = "raid_participants"

    id         = Column(Integer, primary_key=True)
    room_id    = Column(Integer, ForeignKey("raid_rooms.id"), nullable=False)
    user_id    = Column(Integer, ForeignKey("users.id"), nullable=False)
    hero_id    = Column(Integer, ForeignKey("heroes.id"), nullable=False)
    clan_id    = Column(Integer, ForeignKey("clans.id"), nullable=True)

    joined_at  = Column(DateTime, nullable=False, default=datetime.utcnow)
    is_ready   = Column(Boolean, nullable=False, default=False)

    room = relationship("RaidRoom", back_populates="participants")

    __table_args__ = (
        UniqueConstraint("room_id", "hero_id", name="uq_room_hero"),
    )


# ── 9. RaidCoalition ─────────────────────────────────────────────────────────
class RaidCoalition(Base):
    """
    Temporary multi-clan alliance for a specific boss spawn.
    """
    __tablename__ = "raid_coalitions"

    id            = Column(Integer, primary_key=True)
    spawn_id      = Column(Integer, ForeignKey("raid_boss_spawns.id"), nullable=False)
    leader_clan_id = Column(Integer, ForeignKey("clans.id"), nullable=False)

    name          = Column(String(128), nullable=True)
    status        = Column(Enum(CoalitionStatus), nullable=False, default=CoalitionStatus.forming)
    loot_rule     = Column(String(32), nullable=False, default="contribution")

    created_at    = Column(DateTime, nullable=False, default=datetime.utcnow)
    disbanded_at  = Column(DateTime, nullable=True)
    cooldown_until = Column(DateTime, nullable=True)

    clans = relationship("RaidCoalitionClan", back_populates="coalition", cascade="all, delete-orphan")


# ── 10. RaidCoalitionClan ────────────────────────────────────────────────────
class RaidCoalitionClan(Base):
    """
    A clan's slot allocation inside a coalition.
    """
    __tablename__ = "raid_coalition_clans"

    id            = Column(Integer, primary_key=True)
    coalition_id  = Column(Integer, ForeignKey("raid_coalitions.id"), nullable=False)
    clan_id       = Column(Integer, ForeignKey("clans.id"), nullable=False)
    hero_slots    = Column(Integer, nullable=False, default=5)
    accepted      = Column(Boolean, nullable=False, default=False)
    invited_at    = Column(DateTime, nullable=False, default=datetime.utcnow)
    accepted_at   = Column(DateTime, nullable=True)

    coalition = relationship("RaidCoalition", back_populates="clans")

    __table_args__ = (
        UniqueConstraint("coalition_id", "clan_id", name="uq_coalition_clan"),
    )


# ── 11. RaidAccessScore ──────────────────────────────────────────────────────
class RaidAccessScore(Base):
    """
    Raid Access Points (RAP) accumulated by a clan in the current cycle.
    Cycle resets weekly or monthly depending on context.
    """
    __tablename__ = "raid_access_scores"

    id            = Column(Integer, primary_key=True)
    clan_id       = Column(Integer, ForeignKey("clans.id"), nullable=False)
    cycle_key     = Column(String(32), nullable=False)   # e.g. "weekly_2026_W13" or "monthly_2026_03"
    points        = Column(Integer, nullable=False, default=0)
    qualified     = Column(Boolean, nullable=False, default=False)

    updated_at    = Column(DateTime, nullable=False, default=datetime.utcnow)

    __table_args__ = (
        UniqueConstraint("clan_id", "cycle_key", name="uq_clan_cycle"),
    )


# ── 12. RaidBattleLog ────────────────────────────────────────────────────────
class RaidBattleLog(Base):
    """
    Full battle log — phases broken, events, ticks.
    """
    __tablename__ = "raid_battle_logs"

    id         = Column(Integer, primary_key=True)
    room_id    = Column(Integer, ForeignKey("raid_rooms.id"), unique=True, nullable=False)
    spawn_id   = Column(Integer, ForeignKey("raid_boss_spawns.id"), nullable=False)

    outcome       = Column(String(32), nullable=False)
    total_ticks   = Column(Integer, nullable=False, default=0)
    phases_broken = Column(Integer, nullable=False, default=0)
    boss_hp_remaining_pct = Column(Float, nullable=False, default=1.0)

    # Timeline: [{tick, event_type, source, target, value, phase}]
    timeline      = Column(JSON, nullable=False, default=list)
    summary       = Column(JSON, nullable=False, default=dict)   # high-level stats

    created_at    = Column(DateTime, nullable=False, default=datetime.utcnow)

    room  = relationship("RaidRoom", back_populates="battle_log")
    rewards = relationship("RaidRewardRoll", back_populates="battle_log", cascade="all, delete-orphan")


# ── 13. RaidContribution ────────────────────────────────────────────────────
class RaidContribution(Base):
    """
    Per-participant contribution metrics (used for reward scaling).
    """
    __tablename__ = "raid_contributions"

    id               = Column(Integer, primary_key=True)
    room_id          = Column(Integer, ForeignKey("raid_rooms.id"), nullable=False)
    user_id          = Column(Integer, ForeignKey("users.id"), nullable=False)
    hero_id          = Column(Integer, ForeignKey("heroes.id"), nullable=False)

    damage_dealt     = Column(Integer, nullable=False, default=0)
    damage_taken     = Column(Integer, nullable=False, default=0)
    healing_done     = Column(Integer, nullable=False, default=0)
    control_seconds  = Column(Float,   nullable=False, default=0.0)
    mechanic_hits    = Column(Integer, nullable=False, default=0)   # phase mechanics correctly executed
    survival_ticks   = Column(Integer, nullable=False, default=0)
    kills            = Column(Integer, nullable=False, default=0)   # minion kills
    phases_contributed = Column(Integer, nullable=False, default=0)

    # Computed contribution score (set after battle)
    contribution_score = Column(Float, nullable=False, default=0.0)
    contribution_pct   = Column(Float, nullable=False, default=0.0)  # % of total team score
    is_mvp             = Column(Boolean, nullable=False, default=False)

    room = relationship("RaidRoom", back_populates="contributions")

    __table_args__ = (
        UniqueConstraint("room_id", "hero_id", name="uq_contribution_hero"),
    )


# ── 14. RaidRewardRoll ───────────────────────────────────────────────────────
class RaidRewardRoll(Base):
    """
    Record of every reward rolled after a completed raid.
    """
    __tablename__ = "raid_reward_rolls"

    id              = Column(Integer, primary_key=True)
    battle_log_id   = Column(Integer, ForeignKey("raid_battle_logs.id"), nullable=False)
    user_id         = Column(Integer, ForeignKey("users.id"), nullable=True)   # None = clan/coalition reward
    clan_id         = Column(Integer, ForeignKey("clans.id"), nullable=True)

    drop_entry_id   = Column(Integer, ForeignKey("raid_drop_entries.id"), nullable=True)
    item_code       = Column(String(64), nullable=True)
    recipe_code     = Column(String(64), nullable=True)
    artifact_code   = Column(String(64), nullable=True)
    display_name    = Column(String(128), nullable=False)
    quantity        = Column(Integer, nullable=False, default=1)
    rarity          = Column(Enum(DropRarity), nullable=False, default=DropRarity.common)
    ownership       = Column(Enum(DropOwnership), nullable=False, default=DropOwnership.personal)

    rolled_chance   = Column(Float, nullable=False)   # actual chance at roll time
    is_ultra_rare   = Column(Boolean, nullable=False, default=False)

    granted_at      = Column(DateTime, nullable=False, default=datetime.utcnow)

    battle_log = relationship("RaidBattleLog", back_populates="rewards")


# ── 15. RaidBossHistory (aggregate stats per boss) ───────────────────────────
class RaidBossHistory(Base):
    """
    Summarized history entry per boss fight — used for the 'history' UI screen.
    """
    __tablename__ = "raid_boss_history"

    id             = Column(Integer, primary_key=True)
    template_id    = Column(Integer, ForeignKey("raid_boss_templates.id"), nullable=False)
    spawn_id       = Column(Integer, ForeignKey("raid_boss_spawns.id"), nullable=False)
    room_id        = Column(Integer, ForeignKey("raid_rooms.id"), nullable=True)

    outcome        = Column(String(32), nullable=False)   # "victory" | "defeat" | "expired"
    # Who defeated/failed
    clan_names     = Column(JSON, nullable=False, default=list)
    hero_count     = Column(Integer, nullable=False, default=0)
    duration_ticks = Column(Integer, nullable=False, default=0)

    # Boss XP gained from this fight
    xp_gained      = Column(Integer, nullable=False, default=0)
    level_before   = Column(Integer, nullable=False, default=1)
    level_after    = Column(Integer, nullable=False, default=1)
    mutation_gained = Column(String(64), nullable=True)

    occurred_at    = Column(DateTime, nullable=False, default=datetime.utcnow)
