"""
skill_resolver.py — Resolves skill effects, control windows, damage, and kill logic.

Control window model (per spec):
  windup → commit point → release → recovery
  - INTERRUPT is possible during windup
  - REDIRECT is possible during commit
  - PANIC can be applied during channel
  - DOMINATE only on willpower-broken targets
"""
from __future__ import annotations

import random
from typing import TYPE_CHECKING, List, Optional

from .runtime import (
    ActiveEffect, BattleEvent, CastInProgress, ControlType, EventType,
    HeroRuntimeState, HeroState, Vec2,
)

if TYPE_CHECKING:
    from .runtime import BattleInstance

# ── Damage application ────────────────────────────────────────────────────────

def apply_damage(
    attacker: HeroRuntimeState,
    target:   HeroRuntimeState,
    raw_damage: float,
    battle:   "BattleInstance",
    is_basic_attack: bool = False,
    skill_name: str = "",
) -> float:
    """
    Compute effective damage, apply to target HP, check unconscious/death.
    Returns actual damage dealt.
    """
    # Defense mitigation (diminishing returns)
    mit_factor = target.defense / (target.defense + 40.0)
    effective  = raw_damage * (1.0 - mit_factor)

    # Luck crits (attacker)
    crit_chance = min(0.05 + attacker.luck * 0.01, 0.35)
    if random.random() < crit_chance:
        effective *= 1.5

    effective = max(effective, 1.0)
    target.current_hp = max(0.0, target.current_hp - effective)
    attacker.damage_dealt += effective
    target.damage_taken   += effective

    battle.event_log.append(BattleEvent(
        tick       = battle.current_tick,
        event_type = EventType.DAMAGE_APPLIED,
        source_id  = attacker.hero_id,
        target_id  = target.hero_id,
        position   = Vec2(target.position.x, target.position.z),
        payload    = {
            "amount": round(effective, 1),
            "raw":    round(raw_damage, 1),
            "skill":  skill_name,
            "is_basic": is_basic_attack,
        },
    ))

    # Check for unconscious / death
    _check_vitals(target, attacker, battle)
    return effective

def apply_stamina_drain(
    drainer: HeroRuntimeState,
    target:  HeroRuntimeState,
    amount:  float,
    battle:  "BattleInstance",
) -> float:
    drained = min(target.current_stamina, amount)
    target.current_stamina  -= drained
    drainer.current_stamina  = min(drainer.max_stamina, drainer.current_stamina + drained * 0.6)
    battle.event_log.append(BattleEvent(
        tick       = battle.current_tick,
        event_type = EventType.STAMINA_DRAINED,
        source_id  = drainer.hero_id,
        target_id  = target.hero_id,
        position   = Vec2(target.position.x, target.position.z),
        payload    = {"drained": round(drained, 1)},
    ))
    return drained

# ── Vitals check (unconscious / death) ───────────────────────────────────────

def _check_vitals(
    target:   HeroRuntimeState,
    attacker: HeroRuntimeState,
    battle:   "BattleInstance",
) -> None:
    if target.dead:
        return

    hp_pct  = target.current_hp / max(target.max_hp, 1.0)
    st_pct  = target.current_stamina / max(target.max_stamina, 1.0)
    wp      = target.willpower

    # Unconscious trigger
    if not target.unconscious:
        unc = False
        if hp_pct < 0.05:
            unc = True
        elif hp_pct < 0.15 and st_pct < 0.10:
            unc = True
        elif target.willpower_pressure > 25.0 and hp_pct < 0.25:
            unc = True
        elif target.control_state in (ControlType.STUN, ControlType.DOMINATE) and hp_pct < 0.12:
            unc = True
        if unc:
            target.unconscious = True
            target.state       = HeroState.UNCONSCIOUS
            battle.event_log.append(BattleEvent(
                tick       = battle.current_tick,
                event_type = EventType.HERO_UNCONSCIOUS,
                source_id  = attacker.hero_id,
                target_id  = target.hero_id,
                position   = Vec2(target.position.x, target.position.z),
                payload    = {"hp_pct": round(hp_pct, 2)},
            ))

    # Death trigger
    if target.unconscious or hp_pct <= 0.0:
        # Luck + willpower death save (10% per point, max 40%)
        save_chance = min((target.luck * 0.05 + target.willpower * 0.03), 0.40)
        if hp_pct > 0.0 and random.random() < save_chance:
            # Survived — leave unconscious
            target.current_hp = max(1.0, target.max_hp * 0.02)
            return

        _kill_hero(target, attacker, battle)

def _kill_hero(
    victim:   HeroRuntimeState,
    killer:   HeroRuntimeState,
    battle:   "BattleInstance",
) -> None:
    if victim.dead:
        return
    victim.dead        = True
    victim.unconscious = True
    victim.current_hp  = 0.0
    victim.state       = HeroState.DEAD
    victim.death_tick  = battle.current_tick
    killer.kills      += 1

    # Update team alive count
    team = battle.get_team(victim.team_id)
    if team:
        team.alive_count = sum(
            1 for h in battle.heroes.values()
            if h.team_id == victim.team_id and not h.dead
        )

    battle.event_log.append(BattleEvent(
        tick       = battle.current_tick,
        event_type = EventType.HERO_DEAD,
        source_id  = killer.hero_id,
        target_id  = victim.hero_id,
        position   = Vec2(victim.position.x, victim.position.z),
        payload    = {"killer_role": killer.primary_role},
    ))

    # Kill-trigger check
    _check_kill_trigger(killer, victim, battle)

# ── Kill-trigger / absorb ─────────────────────────────────────────────────────

def _check_kill_trigger(
    killer: HeroRuntimeState,
    victim: HeroRuntimeState,
    battle: "BattleInstance",
) -> None:
    """
    Chance for killer to absorb a passive or gain a stat boost.
    Factors: killer.luck, victim.willpower differential.
    """
    base   = 0.05 + killer.luck * 0.02
    wp_mod = max(0.0, (killer.willpower - victim.willpower) * 0.01)
    chance = min(base + wp_mod, 0.40)

    if random.random() > chance:
        return

    # Absorb type: stat shard or skill echo
    absorb_type = random.choice(["stat_shard", "skill_echo"])
    payload: dict = {"absorb_type": absorb_type}
    if absorb_type == "stat_shard":
        stat = random.choice(["attack_power", "speed", "luck", "willpower"])
        boost = random.uniform(0.5, 2.0)
        setattr(killer, stat, getattr(killer, stat) + boost)
        payload["stat"] = stat
        payload["boost"] = round(boost, 2)
    else:
        # Reduce a random cooldown
        if killer.cooldowns:
            sk = random.choice(list(killer.cooldowns.keys()))
            killer.cooldowns[sk] = 0.0
            payload["cd_reset"] = sk

    battle.event_log.append(BattleEvent(
        tick       = battle.current_tick,
        event_type = EventType.KILL_TRIGGER,
        source_id  = killer.hero_id,
        target_id  = victim.hero_id,
        position   = Vec2(killer.position.x, killer.position.z),
        payload    = payload,
    ))

# ── Skill resolution ──────────────────────────────────────────────────────────

def resolve_cast(
    caster:  HeroRuntimeState,
    cast:    CastInProgress,
    battle:  "BattleInstance",
) -> None:
    """Called when a cast completes (elapsed >= windup)."""
    if cast.interrupted:
        battle.event_log.append(BattleEvent(
            tick       = battle.current_tick,
            event_type = EventType.CAST_INTERRUPTED,
            source_id  = caster.hero_id,
            target_id  = cast.target_id,
            position   = Vec2(caster.position.x, caster.position.z),
            payload    = {"skill": cast.skill_name},
        ))
        return

    actual_target_id = cast.redirected_target_id or cast.target_id
    target = battle.hero(actual_target_id) if actual_target_id else None

    # Consume stamina cost from skill
    skill = _find_skill(caster, cast.skill_id)
    if skill:
        cost = skill.get("stamina_cost", 0)
        caster.current_stamina = max(0.0, caster.current_stamina - cost)
        # Set cooldown
        cd = skill.get("cooldown", 0.0)
        if cd > 0:
            caster.cooldowns[cast.skill_id] = cd

    if target is None or target.dead:
        return

    # Apply skill effect based on action type
    fam = (skill or {}).get("family", "COMBAT")
    power = (skill or {}).get("power", caster.attack_power)

    if fam == "COMBAT":
        apply_damage(caster, target, power, battle, skill_name=cast.skill_name)
    elif fam == "CONTROL":
        _apply_control(caster, target, skill or {}, battle)
    elif fam == "DEBUFF":
        _apply_debuff(caster, target, skill or {}, battle)
    elif fam == "BUFF":
        _apply_buff(caster, battle, skill or {})
    elif fam == "TRANSFER":
        drain = power * 0.6
        apply_stamina_drain(caster, target, drain, battle)
    elif fam == "HYBRID":
        apply_damage(caster, target, power * 0.7, battle, skill_name=cast.skill_name)
        _apply_debuff(caster, target, skill or {}, battle)
    else:
        apply_damage(caster, target, power, battle, skill_name=cast.skill_name)

    if actual_target_id != cast.target_id:
        battle.event_log.append(BattleEvent(
            tick       = battle.current_tick,
            event_type = EventType.CAST_REDIRECTED,
            source_id  = caster.hero_id,
            target_id  = actual_target_id,
            position   = Vec2(caster.position.x, caster.position.z),
            payload    = {"original": cast.target_id, "skill": cast.skill_name},
        ))
    else:
        battle.event_log.append(BattleEvent(
            tick       = battle.current_tick,
            event_type = EventType.SKILL_HIT,
            source_id  = caster.hero_id,
            target_id  = actual_target_id,
            position   = Vec2(target.position.x, target.position.z),
            payload    = {"skill": cast.skill_name, "family": fam},
        ))

def resolve_basic_attack(
    attacker: HeroRuntimeState,
    target:   HeroRuntimeState,
    battle:   "BattleInstance",
) -> None:
    """Instant basic attack (no cast time)."""
    apply_damage(attacker, target, attacker.attack_power, battle, is_basic_attack=True)
    battle.event_log.append(BattleEvent(
        tick       = battle.current_tick,
        event_type = EventType.BASIC_ATTACK_HIT,
        source_id  = attacker.hero_id,
        target_id  = target.hero_id,
        position   = Vec2(target.position.x, target.position.z),
        payload    = {},
    ))

# ── Control application ───────────────────────────────────────────────────────

def _apply_control(
    source:  HeroRuntimeState,
    target:  HeroRuntimeState,
    skill:   dict,
    battle:  "BattleInstance",
) -> None:
    ctrl_type_str = skill.get("control_type", "stun")
    try:
        ctrl = ControlType(ctrl_type_str)
    except ValueError:
        ctrl = ControlType.STUN

    # Resistance check
    tier      = skill.get("control_tier", 1)
    resist    = target.willpower * 0.08
    threshold = tier * 0.20
    if random.random() < resist and resist > threshold:
        return  # resisted

    duration = skill.get("control_duration", 1.5)
    target.control_state      = ctrl
    target.willpower_pressure += tier * 4.0

    if ctrl == ControlType.STUN:
        target.state = HeroState.CONTROLLED
        if target.current_cast:
            target.current_cast.interrupted = True

    target.active_effects.append(ActiveEffect(
        effect_id   = f"ctrl_{battle.current_tick}_{source.hero_id}",
        effect_type = "control",
        sub_type    = ctrl.value,
        source_id   = source.hero_id,
        power       = tier,
        duration    = duration,
        control_type = ctrl,
    ))

    target.control_seconds += duration
    team = battle.get_team(source.team_id)
    if team:
        team.total_control_time += duration

    battle.event_log.append(BattleEvent(
        tick       = battle.current_tick,
        event_type = EventType.CONTROL_APPLIED,
        source_id  = source.hero_id,
        target_id  = target.hero_id,
        position   = Vec2(target.position.x, target.position.z),
        payload    = {"control": ctrl.value, "duration": duration},
    ))

def _apply_debuff(
    source: HeroRuntimeState,
    target: HeroRuntimeState,
    skill:  dict,
    battle: "BattleInstance",
) -> None:
    duration = skill.get("duration", 3.0)
    sub_type = skill.get("debuff_type", "slow")
    power    = skill.get("power", 10.0)

    target.active_effects.append(ActiveEffect(
        effect_id   = f"dbf_{battle.current_tick}_{source.hero_id}",
        effect_type = "debuff",
        sub_type    = sub_type,
        source_id   = source.hero_id,
        power       = power,
        duration    = duration,
    ))
    if sub_type == "slow":
        target.speed = max(1.0, target.speed - power * 0.02)

    battle.event_log.append(BattleEvent(
        tick       = battle.current_tick,
        event_type = EventType.DEBUFF_APPLIED,
        source_id  = source.hero_id,
        target_id  = target.hero_id,
        position   = Vec2(target.position.x, target.position.z),
        payload    = {"sub_type": sub_type, "duration": duration},
    ))

def _apply_buff(
    source: HeroRuntimeState,
    battle: "BattleInstance",
    skill:  dict,
) -> None:
    # Buffs applied to self or team
    duration = skill.get("duration", 5.0)
    sub_type = skill.get("buff_type", "speed_up")
    power    = skill.get("power", 10.0)

    source.active_effects.append(ActiveEffect(
        effect_id   = f"buf_{battle.current_tick}_{source.hero_id}",
        effect_type = "buff",
        sub_type    = sub_type,
        source_id   = source.hero_id,
        power       = power,
        duration    = duration,
    ))
    if sub_type == "speed_up":
        source.speed = min(source.speed * 1.3, 12.0)
    elif sub_type == "armor_up":
        source.defense = min(source.defense * 1.25, 60.0)

    battle.event_log.append(BattleEvent(
        tick       = battle.current_tick,
        event_type = EventType.BUFF_APPLIED,
        source_id  = source.hero_id,
        target_id  = source.hero_id,
        position   = Vec2(source.position.x, source.position.z),
        payload    = {"sub_type": sub_type, "duration": duration},
    ))

# ── Interrupt attempt ────────────────────────────────────────────────────────

def attempt_interrupt(
    interrupter: HeroRuntimeState,
    target:      HeroRuntimeState,
    battle:      "BattleInstance",
) -> bool:
    """Try to interrupt target's current cast during windup."""
    if target.current_cast is None:
        return False
    if not target.current_cast.interruptible:
        return False
    if target.current_cast.committed:
        return False  # past the commit point — too late
    target.current_cast.interrupted = True
    battle.event_log.append(BattleEvent(
        tick       = battle.current_tick,
        event_type = EventType.CAST_INTERRUPTED,
        source_id  = interrupter.hero_id,
        target_id  = target.hero_id,
        position   = Vec2(target.position.x, target.position.z),
        payload    = {"skill": target.current_cast.skill_name},
    ))
    return True

# ── Helpers ───────────────────────────────────────────────────────────────────

def _find_skill(hero: HeroRuntimeState, skill_id: int) -> Optional[dict]:
    for s in hero.skills:
        if s["id"] == skill_id:
            return s
    return None

def tick_effects(hero: HeroRuntimeState, dt: float, battle: "BattleInstance") -> None:
    """Advance all active effects, remove expired ones, reset cleared control."""
    expired = []
    for eff in hero.active_effects:
        if not eff.tick(dt):
            expired.append(eff)
            # Undo simple modifiers on expiry
            if eff.sub_type == "slow":
                hero.speed = min(hero.speed + eff.power * 0.02, 12.0)
            elif eff.sub_type == "speed_up":
                hero.speed = max(hero.speed / 1.3, 1.0)
            elif eff.sub_type == "armor_up":
                hero.defense = max(hero.defense / 1.25, 1.0)

    for eff in expired:
        hero.active_effects.remove(eff)
        if eff.control_type and hero.control_state == eff.control_type:
            # Check no other control of same type remains
            still_controlled = any(
                e.control_type == eff.control_type for e in hero.active_effects
            )
            if not still_controlled:
                hero.control_state = None
                if hero.state == HeroState.CONTROLLED:
                    hero.state = HeroState.IDLE
                battle.event_log.append(BattleEvent(
                    tick       = battle.current_tick,
                    event_type = EventType.CONTROL_BROKEN,
                    source_id  = None,
                    target_id  = hero.hero_id,
                    position   = Vec2(hero.position.x, hero.position.z),
                    payload    = {"was": eff.control_type.value},
                ))
