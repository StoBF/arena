"""
hero_ai.py — Per-hero decision-making.

Each tick the simulator calls decide(hero, battle) which:
1. Selects the best target (role-weighted scoring)
2. Picks the best action (skill or basic attack)
3. Sets movement mode
4. Returns movement destination
"""
from __future__ import annotations

import math
import random
from typing import TYPE_CHECKING, List, Optional, Tuple

from .runtime import (
    ActionType, BattleEvent, CastInProgress, ControlType, EventType,
    HeroRuntimeState, HeroState, MovementMode, PendingAction, Vec2,
)
from . import arena as ar

if TYPE_CHECKING:
    from .runtime import BattleInstance

# ── Role constants ────────────────────────────────────────────────────────────

_RETREAT_HP_THRESHOLD    = 0.22   # retreat below this HP%
_RETREAT_STAMINA_THRESHOLD = 0.15  # retreat if stamina this low + HP < 50%
_CHASE_RANGE             = 16.0   # stop chasing beyond this distance
_VISION_RANGE            = 12.0   # default vision radius (overridden by hero.vision)
_FOCUS_BONUS             = 2.0    # extra target score when whole team attacking same enemy

# ── Entry point ───────────────────────────────────────────────────────────────

def decide(hero: HeroRuntimeState, battle: "BattleInstance") -> Optional[Vec2]:
    """
    Run one tick of AI for this hero.
    Updates: hero.state, hero.target_id, hero.movement_mode, hero.desired_pos
    Returns the desired position for this tick (or None if hero can't move).
    """
    if not hero.actionable and hero.state not in (
        HeroState.CONTROLLED, HeroState.UNCONSCIOUS
    ):
        return None
    if hero.state == HeroState.UNCONSCIOUS:
        return None  # can't act while unconscious

    # Already casting — keep going (movement handled by cast phase)
    if hero.current_cast is not None and not hero.current_cast.done:
        if hero.can_move and hero.current_cast.action_type != ActionType.CHANNEL:
            # Ranged cast — can slow-move
            return _maintain_position(hero, battle)
        return None

    # Clear finished cast
    if hero.current_cast and hero.current_cast.done:
        hero.current_cast = None
        hero.state = HeroState.IDLE

    # Panic — erratic movement
    if hero.control_state == ControlType.PANIC:
        hero.state = HeroState.CONTROLLED
        return _panic_move(hero)

    # Should we retreat?
    if _should_retreat(hero, battle):
        hero.state   = HeroState.RETREAT
        hero.movement_mode = MovementMode.RETREAT
        return ar.retreat_position(hero.position, hero.team_id)

    # Select target
    target = _pick_target(hero, battle)
    if target is None:
        hero.state   = HeroState.IDLE
        hero.movement_mode = MovementMode.HOLD_RANGE
        return None

    if hero.target_id != target.hero_id:
        hero.target_id = target.hero_id

    dist = hero.position.distance_to(target.position)

    # Try to use a skill
    best_skill = _pick_skill(hero, target, battle)
    if best_skill and hero.can_cast:
        _start_cast(hero, best_skill, target, battle)
        # During windup, still move toward preferred range
        return _approach_target(hero, target, battle)

    # Basic attack or hold
    if dist <= hero.preferred_range + 0.5:
        hero.state = HeroState.HOLD_POSITION
        hero.movement_mode = MovementMode.HOLD_RANGE
        return ar.jitter(hero.position, 0.2)  # micro-jitter for liveliness
    else:
        hero.state = HeroState.MOVE_TO_TARGET
        hero.movement_mode = MovementMode.ENGAGE
        return _approach_target(hero, target, battle)

# ── Target selection ──────────────────────────────────────────────────────────

def _pick_target(
    hero: HeroRuntimeState, battle: "BattleInstance"
) -> Optional[HeroRuntimeState]:
    enemies = battle.enemies_of(hero.team_id)
    if not enemies:
        return None
    team_focus = _team_focus_target(hero.team_id, battle)
    scored = [(e, _target_score(hero, e, battle, team_focus)) for e in enemies]
    scored.sort(key=lambda x: x[1], reverse=True)
    return scored[0][0] if scored else None

def _target_score(
    hero: HeroRuntimeState,
    target: HeroRuntimeState,
    battle: "BattleInstance",
    team_focus_id: Optional[int],
) -> float:
    """Lower score → less desirable. Positive = desirable."""
    score = 0.0
    dist = hero.position.distance_to(target.position)

    # Distance penalty (further = lower priority)
    score -= dist * 0.5

    # In vision range bonus
    if dist <= hero.vision:
        score += 3.0

    # HP vulnerability bonus
    score += (1.0 - target.hp_pct) * 10.0

    # Stamina vulnerability
    score += (1.0 - target.stamina_pct) * 4.0

    # Willpower vulnerability (good for control skills)
    wp_max = 10.0
    score += (1.0 - target.willpower / wp_max) * 3.0

    # Low HP execute window
    if target.hp_pct < 0.2:
        score += 8.0
    if target.hp_pct < 0.10:
        score += 12.0

    # Currently unconscious — soft target
    if target.unconscious:
        score += 6.0

    # Currently being focused by team
    if team_focus_id and target.hero_id == team_focus_id:
        score += _FOCUS_BONUS

    # Role-specific scoring
    role = hero.primary_role
    trole = target.primary_role

    if role == "VANGUARD":
        # Prefer the front-line target pressing allies
        if trole in ("VANGUARD", "STRIKER"):
            score += 3.0
        # Prefer closer targets (tank engages nearest)
        score -= dist * 0.3

    elif role == "STRIKER":
        # Prefer soft, low-HP targets for execution
        if trole in ("SUPPORT", "CONTROLLER", "TRANSFER"):
            score += 5.0
        score += (1.0 - target.hp_pct) * 8.0

    elif role == "CONTROLLER":
        # Prefer casters and low-willpower targets
        if trole in ("CONTROLLER", "SUPPORT"):
            score += 4.0
        if target.current_cast is not None:
            score += 6.0  # interrupt opportunity
        score += (1.0 - target.willpower / 10.0) * 5.0

    elif role == "SUPPORT":
        # Supports don't attack aggressively — they follow team focus
        if team_focus_id and target.hero_id == team_focus_id:
            score += 8.0
        else:
            score -= 5.0  # deprioritise off-target enemies

    elif role == "TRANSFER":
        # Prefer targets with high stamina (drain) or that threaten allies
        score += target.stamina_pct * 5.0
        if trole == "VANGUARD":
            score += 3.0  # stamina-rich tank is ideal drain target

    return score

def _team_focus_target(team_id: str, battle: "BattleInstance") -> Optional[int]:
    """Return the most-targeted enemy ID for this team."""
    tally: dict[int, int] = {}
    for h in battle.heroes.values():
        if h.team_id == team_id and h.alive and h.target_id:
            tally[h.target_id] = tally.get(h.target_id, 0) + 1
    if not tally:
        return None
    return max(tally, key=lambda k: tally[k])

# ── Skill selection ───────────────────────────────────────────────────────────

def _pick_skill(
    hero: HeroRuntimeState,
    target: HeroRuntimeState,
    battle: "BattleInstance",
) -> Optional[dict]:
    """Return the highest-priority ready skill, or None for basic attack."""
    if not hero.skills:
        return None
    dist = hero.position.distance_to(target.position)
    ready = [
        s for s in hero.skills
        if hero.cooldowns.get(s["id"], 0.0) <= 0.0
        and hero.current_stamina >= s.get("stamina_cost", 0)
        and dist <= s.get("range", 12.0)
    ]
    if not ready:
        return None
    # Priority: control > combat > buff/debuff
    def priority(s: dict) -> int:
        fam = s.get("family", "")
        if fam in ("CONTROL", "INTERRUPT"):
            return 10
        if fam == "COMBAT":
            return 7
        if fam in ("DEBUFF",):
            return 5
        if fam in ("BUFF",):
            return 3
        if fam == "TRANSFER":
            return 4
        return 1
    ready.sort(key=priority, reverse=True)
    return ready[0]

# ── Skill initiation ──────────────────────────────────────────────────────────

def _start_cast(
    hero:  HeroRuntimeState,
    skill: dict,
    target: HeroRuntimeState,
    battle: "BattleInstance",
) -> None:
    cast_time = skill.get("cast_time", 0.4)
    hero.current_cast = CastInProgress(
        skill_id    = skill["id"],
        skill_name  = skill.get("name", "Skill"),
        action_type = _action_type_for_skill(skill),
        target_id   = target.hero_id,
        target_pos  = Vec2(target.position.x, target.position.z),
        windup      = cast_time,
        interruptible = skill.get("interruptible", True),
        redirectable  = skill.get("redirectable", False),
    )
    hero.state = HeroState.CAST_SKILL
    battle.event_log.append(BattleEvent(
        tick       = battle.current_tick,
        event_type = EventType.CAST_STARTED,
        source_id  = hero.hero_id,
        target_id  = target.hero_id,
        position   = Vec2(hero.position.x, hero.position.z),
        payload    = {"skill": skill.get("name"), "cast_time": cast_time},
    ))

def _action_type_for_skill(skill: dict) -> ActionType:
    fam = skill.get("family", "")
    if fam == "CONTROL":
        return ActionType.USE_CONTROL
    if fam == "BUFF":
        return ActionType.USE_BUFF
    if fam == "DEBUFF":
        return ActionType.USE_DEBUFF
    if fam == "TRANSFER":
        return ActionType.USE_TRANSFER
    if fam == "CHANNEL":
        return ActionType.CHANNEL
    return ActionType.USE_COMBAT

# ── Movement helpers ──────────────────────────────────────────────────────────

def _approach_target(
    hero:   HeroRuntimeState,
    target: HeroRuntimeState,
    battle: "BattleInstance",
) -> Vec2:
    desired = ar.desired_engagement_pos(
        hero.position, target.position, hero.preferred_range
    )
    return desired

def _maintain_position(hero: HeroRuntimeState, battle: "BattleInstance") -> Vec2:
    """While casting, stay near current position with micro-jitter."""
    return ar.jitter(hero.position, 0.15)

def _panic_move(hero: HeroRuntimeState) -> Vec2:
    """Erratic random movement during panic."""
    angle = random.uniform(0, 6.28)
    dist  = random.uniform(1.5, 4.0)
    return ar.clamp_to_arena(Vec2(
        hero.position.x + math.cos(angle) * dist,
        hero.position.z + math.sin(angle) * dist,
    ))

def _should_retreat(hero: HeroRuntimeState, battle: "BattleInstance") -> bool:
    if hero.primary_role in ("VANGUARD",):
        # Vanguard retreats only at very low HP
        return hero.hp_pct < 0.12
    if hero.hp_pct < _RETREAT_HP_THRESHOLD:
        return True
    if hero.stamina_pct < _RETREAT_STAMINA_THRESHOLD and hero.hp_pct < 0.5:
        return True
    return False

# ── Support: pick best ally to assist ────────────────────────────────────────

def pick_assist_target(
    hero: HeroRuntimeState, battle: "BattleInstance"
) -> Optional[HeroRuntimeState]:
    """For SUPPORT role: find the most endangered ally."""
    allies = battle.allies_of(hero.team_id, exclude_id=hero.hero_id)
    if not allies:
        return None
    danger = [(a, _ally_danger(a)) for a in allies]
    danger.sort(key=lambda x: x[1], reverse=True)
    most_danger = danger[0]
    if most_danger[1] > 3.0:  # only assist if real danger
        return most_danger[0]
    return None

def _ally_danger(hero: HeroRuntimeState) -> float:
    score = 0.0
    score += (1.0 - hero.hp_pct) * 10.0
    score += (1.0 - hero.stamina_pct) * 4.0
    if hero.control_state:
        score += 5.0
    if hero.state == HeroState.RETREAT:
        score += 4.0
    return score
