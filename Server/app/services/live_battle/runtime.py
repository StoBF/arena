"""
runtime.py — in-memory dataclasses for a live 5v5 battle session.

Nothing here touches the DB.  SQLAlchemy persistence lives in
app/database/models/live_battle.py and is used only to record
final results and event replays.
"""
from __future__ import annotations

import time
import uuid
from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional

# ── Enums ────────────────────────────────────────────────────────────────────

class BattleStatus(str, Enum):
    PENDING    = "pending"
    RUNNING    = "running"
    PAUSED     = "paused"
    FINISHED   = "finished"
    CANCELLED  = "cancelled"

class HeroState(str, Enum):
    IDLE         = "idle"
    MOVE_TO_TARGET = "move_to_target"
    HOLD_POSITION  = "hold_position"
    CAST_SKILL     = "cast_skill"
    CHANNEL_SKILL  = "channel_skill"
    CHASE_TARGET   = "chase_target"
    RETREAT        = "retreat"
    ASSIST         = "assist"
    CONTROLLED     = "controlled"
    UNCONSCIOUS    = "unconscious"
    DEAD           = "dead"

class ControlType(str, Enum):
    STUN        = "stun"
    IMMOBILIZE  = "immobilize"
    SILENCE     = "silence"
    PANIC       = "panic"
    REDIRECT    = "redirect"
    DOMINATE    = "dominate"

class MovementMode(str, Enum):
    ENGAGE        = "engage"
    HOLD_RANGE    = "hold_range"
    KITE          = "kite"
    RETREAT       = "retreat"
    ASSIST        = "assist"
    COLLAPSE      = "collapse"
    REPOSITION    = "reposition"

class EventType(str, Enum):
    MOVE_STARTED       = "move_started"
    TARGET_CHANGED     = "target_changed"
    CAST_STARTED       = "cast_started"
    CAST_INTERRUPTED   = "cast_interrupted"
    CAST_REDIRECTED    = "cast_redirected"
    SKILL_HIT          = "skill_hit"
    BASIC_ATTACK_HIT   = "basic_attack_hit"
    DAMAGE_APPLIED     = "damage_applied"
    BUFF_APPLIED       = "buff_applied"
    DEBUFF_APPLIED     = "debuff_applied"
    CONTROL_APPLIED    = "control_applied"
    CONTROL_BROKEN     = "control_broken"
    STAMINA_DRAINED    = "stamina_drained"
    HERO_UNCONSCIOUS   = "hero_unconscious"
    HERO_DEAD          = "hero_dead"
    KILL_TRIGGER       = "kill_trigger"
    ABSORB_TRIGGER     = "absorb_trigger"
    BATTLE_FINISHED    = "battle_finished"

class ActionType(str, Enum):
    MOVE          = "move"
    BASIC_ATTACK  = "basic_attack"
    USE_COMBAT    = "use_combat"
    USE_BUFF      = "use_buff"
    USE_DEBUFF    = "use_debuff"
    USE_TRANSFER  = "use_transfer"
    USE_CONTROL   = "use_control"
    CHANNEL       = "channel"
    INTERRUPT     = "interrupt"
    RETREAT       = "retreat"
    ASSIST        = "assist"
    HOLD          = "hold"

# ── Position ──────────────────────────────────────────────────────────────────

@dataclass
class Vec2:
    x: float = 0.0
    z: float = 0.0

    def distance_to(self, other: "Vec2") -> float:
        return ((self.x - other.x) ** 2 + (self.z - other.z) ** 2) ** 0.5

    def move_toward(self, target: "Vec2", step: float) -> "Vec2":
        dx = target.x - self.x
        dz = target.z - self.z
        dist = (dx * dx + dz * dz) ** 0.5
        if dist <= step or dist < 0.001:
            return Vec2(target.x, target.z)
        ratio = step / dist
        return Vec2(self.x + dx * ratio, self.z + dz * ratio)

    def lerp(self, other: "Vec2", t: float) -> "Vec2":
        return Vec2(self.x + (other.x - self.x) * t,
                    self.z + (other.z - self.z) * t)

    def to_dict(self) -> Dict[str, float]:
        return {"x": round(self.x, 3), "z": round(self.z, 3)}

# ── Active effects (buffs / debuffs / control) ────────────────────────────────

@dataclass
class ActiveEffect:
    effect_id:   str
    effect_type: str           # "buff" | "debuff" | "control"
    sub_type:    str           # e.g. "speed_up", "stun", "panic"
    source_id:   int           # hero_id that applied it
    power:       float
    duration:    float         # seconds remaining
    control_type: Optional[ControlType] = None
    # For redirect/domination: target override
    redirect_target_id: Optional[int] = None

    def tick(self, dt: float) -> bool:
        """Decrease duration; return True if still active."""
        self.duration -= dt
        return self.duration > 0.0

# ── Active cast / channel ─────────────────────────────────────────────────────

@dataclass
class CastInProgress:
    skill_id:   int
    skill_name: str
    action_type: ActionType
    target_id:  Optional[int]
    target_pos: Optional[Vec2]
    windup:     float          # total windup in seconds
    elapsed:    float = 0.0
    committed:  bool  = False  # past the commit point
    interruptible: bool = True
    redirectable:  bool = False

    @property
    def done(self) -> bool:
        return self.elapsed >= self.windup

# ── Per-hero in-memory state ──────────────────────────────────────────────────

@dataclass
class HeroRuntimeState:
    # Identity
    hero_id:       int
    user_id:       int
    name:          str
    team_id:       str           # "A" | "B"
    primary_role:  str           # "VANGUARD" | "STRIKER" | "CONTROLLER" | "SUPPORT" | "TRANSFER"
    secondary_role: Optional[str] = None

    # Position and movement
    position:      Vec2 = field(default_factory=Vec2)
    desired_pos:   Vec2 = field(default_factory=Vec2)
    rotation:      float = 0.0   # radians, facing direction

    # Core stats (runtime copies, can be modified by effects)
    max_hp:         float = 100.0
    current_hp:     float = 100.0
    max_stamina:    float = 100.0
    current_stamina: float = 100.0
    defense:        float = 10.0
    vision:         float = 12.0   # radius
    speed:          float = 4.0    # units/sec
    agility:        float = 10.0
    luck:           float = 5.0
    willpower:      float = 5.0
    attack_power:   float = 15.0
    attack_interval: float = 1.2  # seconds between basic attacks
    preferred_range: float = 2.0  # role-based preferred combat range

    # Battle AI state
    state:          HeroState = HeroState.IDLE
    movement_mode:  MovementMode = MovementMode.ENGAGE
    target_id:      Optional[int] = None
    assist_target_id: Optional[int] = None  # ally to assist
    last_attack_elapsed: float = 0.0

    # Stamina regen / drain
    stamina_regen_rate: float = 4.0  # per second when not channeling
    stamina_drain_rate: float = 0.0  # when channeling

    # Cooldowns — dict of skill_id → remaining seconds
    cooldowns: Dict[int, float] = field(default_factory=dict)

    # Skills (runtime snapshot from DB load)
    skills: List[Dict[str, Any]] = field(default_factory=list)

    # Active buffs/debuffs/control effects
    active_effects: List[ActiveEffect] = field(default_factory=list)

    # Current cast / channel
    current_cast:    Optional[CastInProgress] = None
    control_state:   Optional[ControlType] = None  # primary control if under CC

    # Vitality tracking
    unconscious:     bool = False
    dead:            bool = False
    death_tick:      Optional[int] = None

    # Pressure / willpower pressure (used for domination checks)
    willpower_pressure: float = 0.0  # cumulative; reset on some events

    # Combat contribution tracking
    damage_dealt:    float = 0.0
    damage_taken:    float = 0.0
    kills:           int   = 0
    control_seconds: float = 0.0

    @property
    def alive(self) -> bool:
        return not self.dead

    @property
    def actionable(self) -> bool:
        """Can make decisions this tick."""
        if self.dead or self.unconscious:
            return False
        if self.control_state in (ControlType.STUN, ControlType.DOMINATE):
            return False
        return True

    @property
    def can_cast(self) -> bool:
        """Can start a new skill."""
        if not self.actionable:
            return False
        if self.control_state == ControlType.SILENCE:
            return False
        if self.current_cast is not None:
            return False
        return True

    @property
    def can_move(self) -> bool:
        if self.dead or self.unconscious:
            return False
        if self.control_state == ControlType.IMMOBILIZE:
            return False
        if self.control_state == ControlType.STUN:
            return False
        return True

    @property
    def hp_pct(self) -> float:
        return self.current_hp / max(self.max_hp, 1.0)

    @property
    def stamina_pct(self) -> float:
        return self.current_stamina / max(self.max_stamina, 1.0)

    def has_effect(self, sub_type: str) -> bool:
        return any(e.sub_type == sub_type for e in self.active_effects)

# ── Per-team runtime state ────────────────────────────────────────────────────

@dataclass
class BattleTeamRuntime:
    team_id:        str       # "A" | "B"
    user_ids:       List[int]
    hero_ids:       List[int]
    alive_count:    int       = 5
    total_damage:   float     = 0.0
    total_control_time: float = 0.0
    morale:         float     = 1.0   # 0.5–1.5 modifier future use

# ── Active skill action (committed, pending resolution) ───────────────────────

@dataclass
class PendingAction:
    action_id:      str
    hero_id:        int
    action_type:    ActionType
    skill_id:       Optional[int]
    target_id:      Optional[int]
    target_pos:     Optional[Vec2]
    commit_tick:    int
    resolve_tick:   int
    resolved:       bool = False
    interrupted:    bool = False
    redirected_target_id: Optional[int] = None

# ── Battle event (for replay / client streaming) ──────────────────────────────

@dataclass
class BattleEvent:
    tick:       int
    event_type: EventType
    source_id:  Optional[int]
    target_id:  Optional[int]
    position:   Optional[Vec2]
    payload:    Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "tick":       self.tick,
            "type":       self.event_type.value,
            "source_id":  self.source_id,
            "target_id":  self.target_id,
            "position":   self.position.to_dict() if self.position else None,
            "payload":    self.payload,
        }

# ── Snapshot (one per tick, sent to clients) ─────────────────────────────────

@dataclass
class HeroSnapshot:
    hero_id:      int
    team_id:      str
    position:     Vec2
    rotation:     float
    state:        str
    target_id:    Optional[int]
    hp:           float
    stamina:      float
    hp_pct:       float
    stamina_pct:  float
    active_cast:  Optional[str]
    active_channel: Optional[str]
    control:      Optional[str]
    unconscious:  bool
    dead:         bool
    effects:      List[str]   # sub_type strings for HUD icons

    def to_dict(self) -> Dict[str, Any]:
        return {
            "hero_id":     self.hero_id,
            "team_id":     self.team_id,
            "pos":         self.position.to_dict(),
            "rot":         round(self.rotation, 3),
            "state":       self.state,
            "target_id":   self.target_id,
            "hp":          round(self.hp, 1),
            "stamina":     round(self.stamina, 1),
            "hp_pct":      round(self.hp_pct, 3),
            "stamina_pct": round(self.stamina_pct, 3),
            "cast":        self.active_cast,
            "channel":     self.active_channel,
            "control":     self.control,
            "unconscious": self.unconscious,
            "dead":        self.dead,
            "effects":     self.effects,
        }

@dataclass
class BattleSnapshot:
    tick:         int
    elapsed_time: float
    heroes:       List[HeroSnapshot]
    events:       List[BattleEvent]
    team_a_alive: int
    team_b_alive: int

    def to_dict(self) -> Dict[str, Any]:
        return {
            "tick":          self.tick,
            "elapsed":       round(self.elapsed_time, 2),
            "heroes":        [h.to_dict() for h in self.heroes],
            "events":        [e.to_dict() for e in self.events],
            "team_a_alive":  self.team_a_alive,
            "team_b_alive":  self.team_b_alive,
        }

# ── Top-level battle instance ─────────────────────────────────────────────────

@dataclass
class BattleInstance:
    battle_id:    str = field(default_factory=lambda: str(uuid.uuid4()))
    map_id:       str = "arena_skirmish"
    mode:         str = "5v5"
    tick_rate:    int = 10          # ticks per second
    current_tick: int = 0
    elapsed_time: float = 0.0
    status:       BattleStatus = BattleStatus.PENDING
    time_limit:   float = 300.0     # 5 minutes

    team_a:       Optional[BattleTeamRuntime] = None
    team_b:       Optional[BattleTeamRuntime] = None
    heroes:       Dict[int, HeroRuntimeState] = field(default_factory=dict)

    winner_team:  Optional[str] = None
    pending_actions: List[PendingAction] = field(default_factory=list)
    event_log:    List[BattleEvent] = field(default_factory=list)

    # Subscribers: list of send-coroutines (WebSocket connections)
    subscribers:  List[Any] = field(default_factory=list)

    @property
    def dt(self) -> float:
        return 1.0 / self.tick_rate

    def get_team(self, team_id: str) -> Optional[BattleTeamRuntime]:
        if team_id == "A":
            return self.team_a
        return self.team_b

    def enemies_of(self, team_id: str) -> List[HeroRuntimeState]:
        opp = "B" if team_id == "A" else "A"
        return [h for h in self.heroes.values() if h.team_id == opp and h.alive]

    def allies_of(self, team_id: str, exclude_id: int = -1) -> List[HeroRuntimeState]:
        return [h for h in self.heroes.values()
                if h.team_id == team_id and h.alive and h.hero_id != exclude_id]

    def hero(self, hero_id: int) -> Optional[HeroRuntimeState]:
        return self.heroes.get(hero_id)
