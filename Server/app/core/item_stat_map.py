"""
Item stat mapping — v1 Item columns → v2 hero stat keys.

The Item model still has v1 column names (bonus_strength, bonus_intelligence,
etc.).  Instead of migrating the DB, we map column names to the v2 stat keys
used in HeroStats (health, stamina, defense, vision, speed, agility, luck,
willpower).

Usage
─────
    from app.core.item_stat_map import ITEM_BONUS_STAT_MAP, equipment_stat_totals

    # Sum equipment bonuses into a v2 stat dict
    totals = equipment_stat_totals(hero.equipment_items)
"""

from __future__ import annotations

from typing import Any, Dict, Iterable

# Column-name on Item  →  v2 stat key (HeroStats column)
ITEM_BONUS_STAT_MAP: Dict[str, str] = {
    "bonus_strength":     "stamina",     # offensive power → stamina
    "bonus_intelligence": "willpower",   # mental power   → willpower
    "bonus_agility":      "agility",
    "bonus_endurance":    "stamina",     # endurance      → stamina (stacks)
    "bonus_speed":        "speed",
    "bonus_health":       "health",
    "bonus_defense":      "defense",
    "bonus_luck":         "luck",
}

# Reverse lookup: v2 stat key → list of Item column names that feed into it.
V2_STAT_SOURCES: Dict[str, list[str]] = {}
for _col, _stat in ITEM_BONUS_STAT_MAP.items():
    V2_STAT_SOURCES.setdefault(_stat, []).append(_col)


def equipment_stat_totals(equipment_items: Iterable[Any]) -> Dict[str, int]:
    """Sum all equipment bonus columns into a v2-keyed stat dict.

    ``equipment_items`` is the hero's ``equipment_items`` relationship
    (list of Equipment ORM objects, each with an ``.item`` back-ref).

    Returns a dict like ``{"stamina": 12, "agility": 5, ...}`` containing
    only stats that have a non-zero bonus.
    """
    totals: Dict[str, int] = {}
    for eq in equipment_items or []:
        item = getattr(eq, "item", None)
        if item is None:
            continue
        for col_name, v2_key in ITEM_BONUS_STAT_MAP.items():
            value = int(getattr(item, col_name, 0) or 0)
            if value:
                totals[v2_key] = totals.get(v2_key, 0) + value
    return totals
