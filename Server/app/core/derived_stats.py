# app/core/derived_stats.py
"""
Derived-stat formulas for the hero system — v2.

All derived stats are computed from the v2 primary stats stored in
``HeroStats`` (health, stamina, defense, vision, speed, agility, luck,
willpower) and the hero's generation level.  They are never persisted.

Equipment bonuses can be passed as a dict and are summed into
each primary stat before the derivation runs.

Derived stats:
    max_hp, initiative, accuracy, evasion, critical_chance,
    critical_resistance, armor_efficiency, recovery_speed, trauma_resistance
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Dict, Optional


@dataclass(frozen=True)
class DerivedStats:
    """Computed from primary stats + generation level + equipment.

    Self-contained dataclass — no dependency on Pydantic schemas so
    that other modules can import it without circular references.
    """
    max_hp: int = 0
    initiative: int = 0
    accuracy: int = 0
    evasion: int = 0
    critical_chance: float = 0.0
    critical_resistance: float = 0.0
    armor_efficiency: float = 0.0
    recovery_speed: float = 0.0
    trauma_resistance: float = 0.0


@dataclass(frozen=True)
class CoreStats:
    """Convenience container for a hero's v2 primary attributes."""
    health: int = 100
    stamina: int = 100
    defense: int = 10
    vision: int = 10
    speed: int = 10
    agility: int = 10
    luck: int = 5
    willpower: int = 5
    generation_level: int = 1


def compute_derived(
    core: CoreStats,
    *,
    equipment_bonuses: Optional[Dict[str, int]] = None,
) -> DerivedStats:
    """Return all derived stats from primary stats + optional equipment.

    The formulas are intentionally simple — balance constants live here so
    they can be tuned without touching DB or schema code.
    """
    eb = equipment_bonuses or {}
    hp  = core.health    + eb.get("health", 0)
    sta = core.stamina   + eb.get("stamina", 0)
    df  = core.defense   + eb.get("defense", 0)
    vis = core.vision    + eb.get("vision", 0)
    spd = core.speed     + eb.get("speed", 0)
    agi = core.agility   + eb.get("agility", 0)
    lck = core.luck      + eb.get("luck", 0)
    wil = core.willpower + eb.get("willpower", 0)
    gl  = core.generation_level

    # ── max_hp ───────────────────────────────────────────────────────
    # Health-heavy, with defense and willpower contributing
    max_hp = int(hp + df * 2 + wil * 3 + gl * 5)

    # ── initiative ───────────────────────────────────────────────────
    # Determines turn order in combat
    initiative = int(spd * 3 + agi * 2 + vis + gl)

    # ── accuracy ─────────────────────────────────────────────────────
    # Chance to land a hit; vision is primary
    accuracy = int(vis * 3 + agi + lck * 0.5 + gl * 0.5)

    # ── evasion ──────────────────────────────────────────────────────
    # Chance to dodge; agility is primary
    evasion = int(agi * 3 + spd + lck * 0.5 + gl * 0.5)

    # ── critical_chance (%) ──────────────────────────────────────────
    # Capped at 75 %
    raw_crit = (lck * 1.5 + vis * 0.8 + agi * 0.3 + gl * 0.1)
    critical_chance = round(min(raw_crit, 75.0), 2)

    # ── critical_resistance (%) ──────────────────────────────────────
    # Reduces incoming crits; willpower + defense
    raw_crit_res = (wil * 1.2 + df * 0.8 + lck * 0.3 + gl * 0.1)
    critical_resistance = round(min(raw_crit_res, 75.0), 2)

    # ── armor_efficiency (0-1 scale) ─────────────────────────────────
    # Diminishing returns via log curve
    raw_armor = (df * 3 + hp * 0.05 + wil * 0.5)
    armor_efficiency = round(1.0 - math.exp(-0.005 * raw_armor), 4)

    # ── recovery_speed ───────────────────────────────────────────────
    # How fast a hero recovers HP between battles
    recovery_speed = round(sta * 0.3 + wil * 0.4 + hp * 0.01 + gl * 0.1, 2)

    # ── trauma_resistance (%) ────────────────────────────────────────
    # Reduces severity of body-part injuries
    raw_trauma = (wil * 2.0 + df * 1.5 + hp * 0.02 + gl * 0.2)
    trauma_resistance = round(min(raw_trauma, 95.0), 2)

    return DerivedStats(
        max_hp=max_hp,
        initiative=initiative,
        accuracy=accuracy,
        evasion=evasion,
        critical_chance=critical_chance,
        critical_resistance=critical_resistance,
        armor_efficiency=armor_efficiency,
        recovery_speed=recovery_speed,
        trauma_resistance=trauma_resistance,
    )


def compute_derived_for_hero(
    hero,
    equipment_bonuses: Optional[Dict[str, int]] = None,
) -> DerivedStats:
    """Convenience wrapper that accepts a Hero ORM instance.

    Expects ``hero.stats`` to be a joined-loaded ``HeroStats`` instance.
    """
    stats = hero.stats
    if stats is None:
        return compute_derived(CoreStats())
    core = CoreStats(
        health=stats.health or 100,
        stamina=stats.stamina or 100,
        defense=stats.defense or 10,
        vision=stats.vision or 10,
        speed=stats.speed or 10,
        agility=stats.agility or 10,
        luck=stats.luck or 5,
        willpower=stats.willpower or 5,
        generation_level=hero.hero_generation_level or 1,
    )
    return compute_derived(core, equipment_bonuses=equipment_bonuses)
