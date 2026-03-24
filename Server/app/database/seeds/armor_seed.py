"""
Seed ArmorItem catalog (T1 starter + T4 set pieces) and ArmorSetBonus rows.
Safe to re-run — upsert by name.
"""
from __future__ import annotations
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert as pg_insert
from app.database.models.armor import ArmorItem, ArmorSetBonus

# ── Armor Items ───────────────────────────────────────────────────────────────

def _t1(name, slot, set_type, bonuses):
    return dict(name=name, slot=slot, tier=1, set_type=set_type,
                is_starter=True, bonuses=bonuses, description=f"Starter {set_type} {slot}.")

def _t4(name, slot, set_type, bonuses):
    return dict(name=name, slot=slot, tier=4, set_type=set_type,
                is_starter=False, bonuses=bonuses, description=f"T4 {set_type} {slot}.")

ARMOR_ITEMS = [
    # ── Proto Bastion (T1 Starter) ──────────────────────────────────────────
    _t1("Proto Bastion Helm",       "helmet",    "bastion",  {"defense": 3, "hp": 15}),
    _t1("Proto Bastion Chestplate", "chest",     "bastion",  {"defense": 5, "hp": 20}),
    _t1("Proto Bastion Leggings",   "legs",      "bastion",  {"defense": 4, "hp": 15}),
    _t1("Proto Bastion Gauntlets",  "gloves",    "bastion",  {"defense": 2, "hp": 10}),
    _t1("Proto Bastion Sabatons",   "boots",     "bastion",  {"defense": 2, "hp": 10}),
    _t1("Proto Bastion Pauldrons",  "shoulders", "bastion",  {"defense": 3, "hp": 12}),
    # ── Proto Pulse (T1 Starter) ────────────────────────────────────────────
    _t1("Proto Pulse Crown",        "helmet",    "pulse",    {"speed": 3, "agility": 2}),
    _t1("Proto Pulse Vest",         "chest",     "pulse",    {"speed": 4, "agility": 3}),
    _t1("Proto Pulse Trousers",     "legs",      "pulse",    {"speed": 4, "agility": 2}),
    _t1("Proto Pulse Gloves",       "gloves",    "pulse",    {"speed": 2, "agility": 2}),
    _t1("Proto Pulse Shoes",        "boots",     "pulse",    {"speed": 4, "agility": 3}),
    _t1("Proto Pulse Mantle",       "shoulders", "pulse",    {"speed": 2, "agility": 2}),
    # ── Proto Rift (T1 Starter) ─────────────────────────────────────────────
    _t1("Proto Rift Circlet",       "helmet",    "rift",     {"willpower": 4}),
    _t1("Proto Rift Robe",          "chest",     "rift",     {"willpower": 5}),
    _t1("Proto Rift Greaves",       "legs",      "rift",     {"willpower": 4}),
    _t1("Proto Rift Gloves",        "gloves",    "rift",     {"willpower": 3}),
    _t1("Proto Rift Sandals",       "boots",     "rift",     {"willpower": 3}),
    _t1("Proto Rift Shoulders",     "shoulders", "rift",     {"willpower": 3}),
    # ── Proto Siphon (T1 Starter) ───────────────────────────────────────────
    _t1("Proto Siphon Visor",       "helmet",    "siphon",   {"stamina": 5}),
    _t1("Proto Siphon Jacket",      "chest",     "siphon",   {"stamina": 8}),
    _t1("Proto Siphon Pants",       "legs",      "siphon",   {"stamina": 6}),
    _t1("Proto Siphon Gauntlets",   "gloves",    "siphon",   {"stamina": 4}),
    _t1("Proto Siphon Boots",       "boots",     "siphon",   {"stamina": 5}),
    _t1("Proto Siphon Shoulders",   "shoulders", "siphon",   {"stamina": 4}),
    # ── Proto Predator (T1 Starter) ─────────────────────────────────────────
    _t1("Proto Predator Hood",      "helmet",    "predator", {"agility": 3, "strength": 3}),
    _t1("Proto Predator Cuirass",   "chest",     "predator", {"agility": 4, "strength": 4}),
    _t1("Proto Predator Greaves",   "legs",      "predator", {"agility": 3, "strength": 3}),
    _t1("Proto Predator Claws",     "gloves",    "predator", {"agility": 3, "strength": 2}),
    _t1("Proto Predator Treads",    "boots",     "predator", {"agility": 4, "strength": 2}),
    _t1("Proto Predator Flares",    "shoulders", "predator", {"agility": 2, "strength": 3}),
    # ── Proto Astral (T1 Starter, balanced) ─────────────────────────────────
    _t1("Proto Astral Helm",        "helmet",    "astral",   {"defense": 2, "willpower": 2, "hp": 8}),
    _t1("Proto Astral Vest",        "chest",     "astral",   {"defense": 3, "stamina": 4, "hp": 10}),
    _t1("Proto Astral Pants",       "legs",      "astral",   {"defense": 2, "stamina": 3, "hp": 8}),
    _t1("Proto Astral Gloves",      "gloves",    "astral",   {"defense": 1, "agility": 2, "hp": 6}),
    _t1("Proto Astral Boots",       "boots",     "astral",   {"speed": 2, "agility": 2, "hp": 6}),
    _t1("Proto Astral Shoulders",   "shoulders", "astral",   {"defense": 2, "willpower": 1, "hp": 7}),

    # ── T4 Bastion of the Black Star ────────────────────────────────────────
    _t4("Black Star Helm",          "helmet",    "bastion",  {"defense": 18, "hp": 80}),
    _t4("Black Star Carapace",      "chest",     "bastion",  {"defense": 28, "hp": 120, "stamina": 10}),
    _t4("Black Star Leg Frame",     "legs",      "bastion",  {"defense": 22, "hp": 90}),
    _t4("Black Star Grips",         "gloves",    "bastion",  {"defense": 14, "hp": 60}),
    _t4("Black Star Striders",      "boots",     "bastion",  {"defense": 14, "hp": 60}),
    _t4("Black Star Aegis Shoulders","shoulders", "bastion", {"defense": 18, "hp": 70}),

    # ── T4 Pulse of Orion ───────────────────────────────────────────────────
    _t4("Orion Pulse Crown",        "helmet",    "pulse",    {"speed": 12, "agility": 8}),
    _t4("Orion Pulse Coreplate",    "chest",     "pulse",    {"speed": 16, "agility": 10, "hp": 50}),
    _t4("Orion Pulse Weave",        "legs",      "pulse",    {"speed": 14, "agility": 9}),
    _t4("Orion Pulse Conductors",   "gloves",    "pulse",    {"speed": 10, "agility": 7}),
    _t4("Orion Pulse Runners",      "boots",     "pulse",    {"speed": 16, "agility": 10}),
    _t4("Orion Pulse Vanes",        "shoulders", "pulse",    {"speed": 10, "agility": 7}),

    # ── T4 Rift Shepherd Regalia ────────────────────────────────────────────
    _t4("Rift Shepherd Halo",       "helmet",    "rift",     {"willpower": 18, "hp": 40}),
    _t4("Rift Shepherd Vestment",   "chest",     "rift",     {"willpower": 24, "hp": 60}),
    _t4("Rift Shepherd Flux Greaves","legs",      "rift",    {"willpower": 20, "hp": 50}),
    _t4("Rift Shepherd Hands",      "gloves",    "rift",     {"willpower": 15, "hp": 35}),
    _t4("Rift Shepherd Steps",      "boots",     "rift",     {"willpower": 15, "hp": 35}),
    _t4("Rift Shepherd Mantles",    "shoulders", "rift",     {"willpower": 16, "hp": 38}),

    # ── T4 Siphon Maw Array ─────────────────────────────────────────────────
    _t4("Siphon Maw Visor",         "helmet",    "siphon",   {"stamina": 25, "hp": 45}),
    _t4("Siphon Maw Chassis",       "chest",     "siphon",   {"stamina": 35, "hp": 65}),
    _t4("Siphon Maw Tendons",       "legs",      "siphon",   {"stamina": 28, "hp": 55}),
    _t4("Siphon Maw Claws",         "gloves",    "siphon",   {"stamina": 20, "hp": 40}),
    _t4("Siphon Maw Tracks",        "boots",     "siphon",   {"stamina": 22, "hp": 42}),
    _t4("Siphon Maw Reservoirs",    "shoulders", "siphon",   {"stamina": 24, "hp": 44}),

    # ── T4 Predator Eclipse Suit ────────────────────────────────────────────
    _t4("Eclipse Hunter Mask",      "helmet",    "predator", {"agility": 14, "strength": 12}),
    _t4("Eclipse Hunter Shell",     "chest",     "predator", {"agility": 18, "strength": 16, "hp": 55}),
    _t4("Eclipse Hunter Spinewrap", "legs",      "predator", {"agility": 15, "strength": 13}),
    _t4("Eclipse Hunter Talons",    "gloves",    "predator", {"agility": 13, "strength": 11}),
    _t4("Eclipse Hunter Treads",    "boots",     "predator", {"agility": 16, "strength": 12}),
    _t4("Eclipse Hunter Flares",    "shoulders", "predator", {"agility": 12, "strength": 14}),
]

# ── Set Bonuses ───────────────────────────────────────────────────────────────

SET_BONUSES = [
    # Bastion
    dict(set_type="bastion", pieces_required=2, bonuses={"defense": 15},
         description="+Defense"),
    dict(set_type="bastion", pieces_required=4, bonuses={"stamina": 20, "control_resistance": 10},
         description="+Stamina, +Control Resistance"),
    dict(set_type="bastion", pieces_required=6, bonuses={"buff_duration_pct": 20, "control_reduction_pct": 15},
         description="Incoming control weakened, ally buffs last longer"),
    # Pulse
    dict(set_type="pulse", pieces_required=2, bonuses={"speed": 12},
         description="+Speed"),
    dict(set_type="pulse", pieces_required=4, bonuses={"cooldown_reduction_pct": 15},
         description="-Cooldown on combat skills"),
    dict(set_type="pulse", pieces_required=6, bonuses={"cast_speed_pct": 20},
         description="+Cast speed / faster skill release windows"),
    # Rift
    dict(set_type="rift", pieces_required=2, bonuses={"willpower": 15},
         description="+Willpower"),
    dict(set_type="rift", pieces_required=4, bonuses={"control_success_pct": 15},
         description="+Control success chance"),
    dict(set_type="rift", pieces_required=6, bonuses={"control_stamina_cost_pct": -20},
         description="Lower stamina cost on control skills"),
    # Siphon
    dict(set_type="siphon", pieces_required=2, bonuses={"transfer_conductivity": 10},
         description="+Transfer conductivity"),
    dict(set_type="siphon", pieces_required=4, bonuses={"drain_effectiveness_pct": 20},
         description="+Drain effectiveness"),
    dict(set_type="siphon", pieces_required=6, bonuses={"transfer_stamina_cost_pct": -15},
         description="Transfer skills cheaper on stamina"),
    # Predator
    dict(set_type="predator", pieces_required=2, bonuses={"agility": 12},
         description="+Agility"),
    dict(set_type="predator", pieces_required=4, bonuses={"execute_damage_pct": 25},
         description="+Execute damage"),
    dict(set_type="predator", pieces_required=6, bonuses={"overkill_conversion_pct": 30},
         description="+Kill-trigger / overkill synergy"),
    # Astral (balanced starter set — no T4 exists yet, but bonuses defined)
    dict(set_type="astral", pieces_required=2, bonuses={"defense": 5, "willpower": 5},
         description="+Defense, +Willpower"),
    dict(set_type="astral", pieces_required=4, bonuses={"hp": 60, "stamina": 15},
         description="+HP, +Stamina"),
    dict(set_type="astral", pieces_required=6, bonuses={"all_stats_pct": 5},
         description="+5% all stats"),
]


async def seed_armor(db: AsyncSession) -> dict:
    item_count = 0
    for row in ARMOR_ITEMS:
        stmt = (
            pg_insert(ArmorItem)
            .values(**row)
            .on_conflict_do_nothing(index_elements=["name"])
        )
        result = await db.execute(stmt)
        item_count += result.rowcount

    bonus_count = 0
    for row in SET_BONUSES:
        # Upsert by (set_type, pieces_required)
        stmt = (
            pg_insert(ArmorSetBonus)
            .values(**row)
            .on_conflict_do_update(
                index_elements=["set_type", "pieces_required"],
                set_=dict(bonuses=row["bonuses"], description=row["description"])
            )
        )
        result = await db.execute(stmt)
        bonus_count += result.rowcount

    await db.commit()
    return {"items": item_count, "bonuses": bonus_count}
