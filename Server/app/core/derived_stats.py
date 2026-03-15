# app/core/derived_stats.py
"""
Derived-stat formulas for the hero system.

All derived stats are computed from primary stats and never persisted.
Equipment bonuses can be passed separately and summed in before calculation.

Primary stats (S.P.E.I.A.L.W):
    strength, perception, endurance, intelligence, agility, luck, willpower

Derived stats:
    max_hp, initiative, accuracy, evasion, critical_chance,
    critical_resistance, armor_efficiency, recovery_speed, trauma_resistance
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Dict, Optional

from app.schemas.hero import DerivedStats


@dataclass(frozen=True)
class PrimaryStats:
    """Convenience container for a hero's primary attributes."""
    strength: int = 0
    perception: int = 0
    endurance: int = 0
    intelligence: int = 0
    agility: int = 0
    luck: int = 0
    willpower: int = 0
    level: int = 1


def compute_derived(
    primary: PrimaryStats,
    *,
    equipment_bonuses: Optional[Dict[str, int]] = None,
) -> DerivedStats:
    """Return all derived stats from primary stats + optional equipment.

    The formulas are intentionally simple — balance constants live here so
    they can be tuned without touching DB or schema code.
    """
    # Merge equipment bonuses into effective values
    eb = equipment_bonuses or {}
    s = primary.strength + eb.get("strength", 0)
    p = primary.perception + eb.get("perception", 0)
    e = primary.endurance + eb.get("endurance", 0)
    i = primary.intelligence + eb.get("intelligence", 0)
    a = primary.agility + eb.get("agility", 0)
    l = primary.luck + eb.get("luck", 0)
    w = primary.willpower + eb.get("willpower", 0)
    lvl = primary.level

    # ── max_hp ───────────────────────────────────────────────────────
    # Endurance-heavy, with strength and willpower contributing
    max_hp = int(50 + e * 8 + s * 2 + w * 3 + lvl * 5)

    # ── initiative ───────────────────────────────────────────────────
    # Determines turn order in combat
    initiative = int(a * 3 + p * 2 + l + lvl)

    # ── accuracy ─────────────────────────────────────────────────────
    # Chance to land a hit; perception is primary
    accuracy = int(p * 3 + a + i * 0.5 + lvl * 0.5)

    # ── evasion ──────────────────────────────────────────────────────
    # Chance to dodge; agility is primary
    evasion = int(a * 3 + p + l * 0.5 + lvl * 0.5)

    # ── critical_chance (%) ──────────────────────────────────────────
    # Capped at 75%
    raw_crit = (l * 1.5 + p * 0.8 + a * 0.3 + lvl * 0.1)
    critical_chance = round(min(raw_crit, 75.0), 2)

    # ── critical_resistance (%) ──────────────────────────────────────
    # Reduces incoming crits; willpower + endurance
    raw_crit_res = (w * 1.2 + e * 0.8 + l * 0.3 + lvl * 0.1)
    critical_resistance = round(min(raw_crit_res, 75.0), 2)

    # ── armor_efficiency (0-1 scale) ─────────────────────────────────
    # Diminishing returns via log curve
    raw_armor = (e * 2 + s * 1.5 + w * 0.5)
    armor_efficiency = round(1.0 - math.exp(-0.005 * raw_armor), 4)

    # ── recovery_speed ───────────────────────────────────────────────
    # How fast a hero recovers HP between battles
    recovery_speed = round(e * 0.6 + w * 0.4 + i * 0.2 + lvl * 0.1, 2)

    # ── trauma_resistance (%) ────────────────────────────────────────
    # Reduces severity of body-part injuries
    raw_trauma = (w * 2.0 + e * 1.0 + s * 0.5 + lvl * 0.2)
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


def compute_derived_for_hero(hero, equipment_bonuses: Optional[Dict[str, int]] = None) -> DerivedStats:
    """Convenience wrapper that accepts a Hero ORM instance."""
    primary = PrimaryStats(
        strength=hero.strength or 0,
        perception=hero.perception or 0,
        endurance=hero.endurance or 0,
        intelligence=hero.intelligence or 0,
        agility=hero.agility or 0,
        luck=hero.luck or 0,
        willpower=hero.willpower or 0,
        level=hero.level or 1,
    )
    return compute_derived(primary, equipment_bonuses=equipment_bonuses)
