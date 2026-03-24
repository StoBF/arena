"""
Raid Boss Catalog — all 9 starter bosses fully defined.
This is the single source of truth for boss stats, phases, and drop tables.
Used by the seeder (migration) and by the battle/reward services.
"""
from __future__ import annotations

from typing import Any, Dict, List

# ── Drop rarity shortcuts ─────────────────────────────────────────────────────
C  = "common"
U  = "uncommon"
R  = "rare"
E  = "epic"
L  = "legendary"
M  = "mythic"

# ── Ownership shortcuts ───────────────────────────────────────────────────────
PER  = "personal"
CLN  = "clan"
COA  = "coalition"
WGT  = "weighted"


def _phase(number: int, trigger_hp_pct: float, name: str,
           modifiers: Dict, abilities: List[str],
           arena_changes: Dict | None = None) -> Dict:
    return {
        "phase_number":   number,
        "trigger_hp_pct": trigger_hp_pct,
        "name":           name,
        "modifiers":      modifiers,
        "abilities":      abilities,
        "arena_changes":  arena_changes or {},
        "description":    name,
    }


def _drop(display_name: str, rarity: str, ownership: str,
          drop_group: str, base_chance: float,
          min_qty: int = 1, max_qty: int = 1,
          item_code: str | None = None, recipe_code: str | None = None,
          artifact_code: str | None = None,
          bonus_conditions: List[Dict] | None = None,
          is_guaranteed: bool = False) -> Dict:
    return {
        "display_name":      display_name,
        "rarity":            rarity,
        "ownership":         ownership,
        "drop_group":        drop_group,
        "base_chance":       base_chance,
        "min_qty":           min_qty,
        "max_qty":           max_qty,
        "item_code":         item_code or display_name.lower().replace(" ", "_"),
        "recipe_code":       recipe_code,
        "artifact_code":     artifact_code,
        "bonus_conditions":  bonus_conditions or [],
        "is_guaranteed":     is_guaranteed,
    }


# ─────────────────────────────────────────────────────────────────────────────
# BOSS CATALOG
# ─────────────────────────────────────────────────────────────────────────────

BOSS_CATALOG: List[Dict[str, Any]] = [

    # ── 1. Stone Colossus (hourly) ────────────────────────────────────────────
    {
        "code":      "stone_colossus",
        "name":      "Stone Colossus",
        "category":  "hourly",
        "archetype": "tank",
        "max_clans":  1,
        "max_heroes": 5,
        "num_phases": 2,
        "base_level": 1,
        "base_hp":    18000,
        "base_armor": 0.30,
        "base_damage": 420,
        "base_speed":  0.70,
        "base_xp":     800,
        "spawn_config": {"interval_hours": 1, "window_minutes": 15},
        "requires_qualification": False,
        "min_access_points": 0,
        "description": "A towering stone guardian. Extremely high armor, punishes melee fighters.",
        "lore": "Carved from the bones of the first mountain, it has guarded the ancient vault since time immemorial.",
        "phases": [
            _phase(1, 1.00, "Stone Fortress",
                   {"damage_mult": 1.0, "armor_mult": 1.0},
                   ["ground_slam", "boulder_throw"]),
            _phase(2, 0.50, "Shattered Titan",
                   {"damage_mult": 1.40, "armor_mult": 0.70, "speed_mult": 1.20},
                   ["rock_storm", "seismic_shockwave"],
                   {"aoe_debris": True}),
        ],
        "drops": [
            _drop("Stone Core",        C, PER, "core",      0.70, 1, 3, is_guaranteed=True),
            _drop("Shell Fragment",    U, PER, "material",  0.55, 1, 2),
            _drop("Colossus Ore",      R, PER, "material",  0.30, 1, 2,
                  bonus_conditions=[{"condition": "boss_level_gte", "value": 5, "bonus": 0.05}]),
            _drop("Heavy Cuirass Recipe", E, CLN, "recipe", 0.08,
                  recipe_code="heavy_cuirass",
                  bonus_conditions=[{"condition": "no_deaths", "value": True, "bonus": 0.04}]),
        ],
    },

    # ── 2. Blood Hunter (hourly) ──────────────────────────────────────────────
    {
        "code":      "blood_hunter",
        "name":      "Blood Hunter",
        "category":  "hourly",
        "archetype": "hunter",
        "max_clans":  1,
        "max_heroes": 5,
        "num_phases": 2,
        "base_level": 1,
        "base_hp":    14000,
        "base_armor": 0.10,
        "base_damage": 680,
        "base_speed":  1.50,
        "base_xp":     850,
        "spawn_config": {"interval_hours": 1, "window_minutes": 15},
        "requires_qualification": False,
        "min_access_points": 0,
        "description": "A fast predator that focuses wounded heroes. High burst, lethal finishers.",
        "lore": "It hunts by the scent of blood. The weaker the prey, the faster it strikes.",
        "phases": [
            _phase(1, 1.00, "Stalking Predator",
                   {"damage_mult": 1.0, "speed_mult": 1.5},
                   ["pounce", "hemorrhage"]),
            _phase(2, 0.40, "Bloodlust Unleashed",
                   {"damage_mult": 1.60, "speed_mult": 1.80, "lifesteal": 0.20},
                   ["execute_strike", "blood_frenzy", "death_leap"]),
        ],
        "drops": [
            _drop("Hunter's Blood",       C, PER, "core",     0.70, 1, 3, is_guaranteed=True),
            _drop("Predator Claws",       U, PER, "material", 0.50, 1, 2),
            _drop("Trophy Neural Node",   R, PER, "material", 0.25, 1, 1),
            _drop("Hunter Gauntlets Recipe", E, CLN, "recipe", 0.07,
                  recipe_code="hunter_gauntlets"),
        ],
    },

    # ── 3. Queen of the Swarm (hourly) ────────────────────────────────────────
    {
        "code":      "swarm_queen",
        "name":      "Queen of the Swarm",
        "category":  "hourly",
        "archetype": "swarm",
        "max_clans":  1,
        "max_heroes": 5,
        "num_phases": 2,
        "base_level": 1,
        "base_hp":    12000,
        "base_armor": 0.05,
        "base_damage": 320,
        "base_speed":  1.10,
        "base_xp":     780,
        "spawn_config": {"interval_hours": 1, "window_minutes": 15},
        "requires_qualification": False,
        "min_access_points": 0,
        "description": "Summons endless waves of swarm minions. Overwhelms weak teams.",
        "lore": "She is the hive. Kill her children and she will only grow angrier.",
        "phases": [
            _phase(1, 1.00, "Swarm Flood",
                   {"summon_waves": 3, "damage_mult": 1.0},
                   ["spawn_drones", "acid_spit"]),
            _phase(2, 0.45, "Hive Mother's Wrath",
                   {"summon_waves": 6, "damage_mult": 1.30, "aoe_acid": True},
                   ["spawn_elite_drones", "swarm_surge", "queen_screech"],
                   {"acid_puddles": True}),
        ],
        "drops": [
            _drop("Swarm Chitin",        C, PER, "core",     0.70, 1, 4, is_guaranteed=True),
            _drop("Mutation Egg",        U, PER, "material", 0.45, 1, 2),
            _drop("Poison Gland",        R, PER, "material", 0.28, 1, 1),
            _drop("Swarm Boots Recipe",  E, CLN, "recipe",   0.07,
                  recipe_code="swarm_boots"),
        ],
    },

    # ── 4. Storm Archon (12-hour) ─────────────────────────────────────────────
    {
        "code":      "storm_archon",
        "name":      "Storm Archon",
        "category":  "half_day",
        "archetype": "mage",
        "max_clans":  2,
        "max_heroes": 10,
        "num_phases": 3,
        "base_level": 5,
        "base_hp":    40000,
        "base_armor": 0.15,
        "base_damage": 900,
        "base_speed":  1.20,
        "base_xp":     2500,
        "spawn_config": {"interval_hours": 12, "window_minutes": 30},
        "requires_qualification": False,
        "min_access_points": 100,
        "description": "Elemental mage boss. AoE lightning fields, spatial control, storm bursts.",
        "lore": "Once a scholar of forbidden storm arts, now an immortal conductor of destruction.",
        "phases": [
            _phase(1, 1.00, "Gathering Storm",
                   {"damage_mult": 1.0, "aoe_fields": 2},
                   ["lightning_bolt", "static_field"]),
            _phase(2, 0.65, "Tempest Awakening",
                   {"damage_mult": 1.35, "aoe_fields": 4, "stun_chance": 0.25},
                   ["chain_lightning", "storm_pillar", "thunder_clap"],
                   {"lightning_zones": True}),
            _phase(3, 0.30, "Eye of the Maelstrom",
                   {"damage_mult": 1.70, "aoe_fields": 7, "stun_chance": 0.40},
                   ["apocalypse_storm", "cyclone_prison", "overcharge"],
                   {"arena_electrified": True, "safe_zones": 2}),
        ],
        "drops": [
            _drop("Storm Core",          C, PER, "core",     0.65, 1, 2, is_guaranteed=True),
            _drop("Thunder Crystal",     U, PER, "material", 0.45, 1, 2),
            _drop("Electroplasma",       R, PER, "material", 0.30, 1, 2),
            _drop("Storm Helmet Recipe", E, CLN, "recipe",   0.10,
                  recipe_code="storm_helmet",
                  bonus_conditions=[{"condition": "all_clans_present", "value": True, "bonus": 0.05}]),
            _drop("Storm Archon Essence", E, CLN, "material", 0.12, 1, 1),
        ],
    },

    # ── 5. Flesh Devourer (12-hour) ───────────────────────────────────────────
    {
        "code":      "flesh_devourer",
        "name":      "Flesh Devourer",
        "category":  "half_day",
        "archetype": "parasite",
        "max_clans":  2,
        "max_heroes": 10,
        "num_phases": 3,
        "base_level": 5,
        "base_hp":    35000,
        "base_armor": 0.12,
        "base_damage": 820,
        "base_speed":  1.00,
        "base_xp":     2600,
        "spawn_config": {"interval_hours": 12, "window_minutes": 30},
        "requires_qualification": False,
        "min_access_points": 100,
        "description": "Evolves mid-battle. Gains power from hero corpses. Shape-shifter.",
        "lore": "It was once many things. Now it is one hunger.",
        "phases": [
            _phase(1, 1.00, "Larval Form",
                   {"damage_mult": 1.0, "regen": 0.01},
                   ["flesh_lash", "infect"]),
            _phase(2, 0.60, "Evolved Parasite",
                   {"damage_mult": 1.40, "regen": 0.02, "absorb_kills": True},
                   ["bone_spear", "devour", "mutate"],
                   {"corpse_spawns": True}),
            _phase(3, 0.25, "Apex Abomination",
                   {"damage_mult": 1.80, "regen": 0.03, "absorb_kills": True,
                    "heal_debuff": 0.50},
                   ["consume_all", "shape_shift", "plague_aura"],
                   {"heal_suppression": True}),
        ],
        "drops": [
            _drop("Living Tissue",         C, PER, "core",     0.65, 1, 3, is_guaranteed=True),
            _drop("Mutation Heart",        U, PER, "material", 0.40, 1, 1),
            _drop("Evolution Enzyme",      R, PER, "material", 0.25, 1, 1),
            _drop("Mutation Pants Recipe", E, CLN, "recipe",   0.09,
                  recipe_code="mutation_pants"),
            _drop("Parasite Essence",      E, CLN, "material", 0.12, 1, 1),
        ],
    },

    # ── 6. Rift Keeper (12-hour) ──────────────────────────────────────────────
    {
        "code":      "rift_keeper",
        "name":      "Rift Keeper",
        "category":  "half_day",
        "archetype": "judge",
        "max_clans":  2,
        "max_heroes": 10,
        "num_phases": 3,
        "base_level": 5,
        "base_hp":    38000,
        "base_armor": 0.20,
        "base_damage": 760,
        "base_speed":  1.10,
        "base_xp":     2700,
        "spawn_config": {"interval_hours": 12, "window_minutes": 30},
        "requires_qualification": False,
        "min_access_points": 100,
        "description": "Spatial controller. Teleports, rifts, traps. Forces disciplined positioning.",
        "lore": "It is the lock on a door between worlds. It does not tolerate trespassers.",
        "phases": [
            _phase(1, 1.00, "Rift Sentinel",
                   {"damage_mult": 1.0, "teleport_cd": 8.0},
                   ["void_slash", "rift_step"]),
            _phase(2, 0.55, "Dimension Ripper",
                   {"damage_mult": 1.45, "teleport_cd": 5.0, "trap_zones": 3},
                   ["spatial_crush", "rift_trap", "void_pull"],
                   {"rift_zones": True}),
            _phase(3, 0.25, "Collapse Protocol",
                   {"damage_mult": 1.75, "teleport_cd": 3.0, "trap_zones": 6,
                    "arena_shrink": True},
                   ["dimension_collapse", "mass_rift", "spatial_annihilation"],
                   {"arena_collapsing": True}),
        ],
        "drops": [
            _drop("Rift Shard",          C, PER, "core",     0.65, 1, 3, is_guaranteed=True),
            _drop("Spatial Core",        U, PER, "material", 0.42, 1, 2),
            _drop("Warped Metal",        R, PER, "material", 0.28, 1, 1),
            _drop("Rift Belt Recipe",    E, CLN, "recipe",   0.10,
                  recipe_code="rift_belt"),
            _drop("Rift Keeper Shard",   E, CLN, "material", 0.14, 1, 1),
        ],
    },

    # ── 7. Synthetic Titan (weekly) ───────────────────────────────────────────
    {
        "code":      "synthetic_titan",
        "name":      "Synthetic Titan",
        "category":  "weekly",
        "archetype": "tank",
        "max_clans":  3,
        "max_heroes": 15,
        "num_phases": 4,
        "base_level": 12,
        "base_hp":    120000,
        "base_armor": 0.45,
        "base_damage": 1800,
        "base_speed":  0.80,
        "base_xp":     10000,
        "spawn_config": {"interval_hours": 168, "window_minutes": 60},  # weekly
        "requires_qualification": True,
        "min_access_points": 500,
        "description": "Epic super-tank. 4 phases, destructible armor plating, massive explosions.",
        "lore": "Assembled in a forgotten forge-city. Its creators are long dead. It is not.",
        "phases": [
            _phase(1, 1.00, "Armored Colossus",
                   {"damage_mult": 1.0, "armor_mult": 2.0},
                   ["titan_slam", "missile_salvo"]),
            _phase(2, 0.70, "Armor Breach",
                   {"damage_mult": 1.30, "armor_mult": 1.40, "aoe_radius": 1.5},
                   ["overload_burst", "chain_stomp", "suppressive_fire"],
                   {"explosion_fields": True}),
            _phase(3, 0.40, "Core Exposed",
                   {"damage_mult": 1.60, "armor_mult": 0.80, "berserker": True},
                   ["core_blast", "titan_rage", "gravity_anchor"],
                   {"arena_shaking": True}),
            _phase(4, 0.15, "Final Protocol",
                   {"damage_mult": 2.20, "armor_mult": 0.40, "enrage": True},
                   ["nuclear_output", "self_destruct_sequence", "titan_requiem"],
                   {"arena_burning": True, "safe_zones": 1}),
        ],
        "drops": [
            _drop("Titan Heart",           U, PER, "core",      0.55, 1, 1, is_guaranteed=True),
            _drop("Synthetic Armor Plate", R, PER, "material",  0.45, 1, 2),
            _drop("Titan Core",            E, CLN, "material",  0.30, 1, 1),
            _drop("Titan Mk.I Set Recipe", E, CLN, "recipe",    0.18,
                  recipe_code="titan_mk1_set",
                  bonus_conditions=[{"condition": "no_deaths", "value": True, "bonus": 0.07}]),
            _drop("Rebirth Artifact",      L, WGT, "ultra_rare", 0.04,
                  artifact_code="rebirth_artifact",
                  bonus_conditions=[{"condition": "boss_level_gte", "value": 15, "bonus": 0.02}]),
        ],
    },

    # ── 8. Nameless Judge (weekly) ────────────────────────────────────────────
    {
        "code":      "nameless_judge",
        "name":      "Nameless Judge",
        "category":  "weekly",
        "archetype": "judge",
        "max_clans":  3,
        "max_heroes": 15,
        "num_phases": 4,
        "base_level": 12,
        "base_hp":    100000,
        "base_armor": 0.25,
        "base_damage": 2200,
        "base_speed":  1.30,
        "base_xp":     11000,
        "spawn_config": {"interval_hours": 168, "window_minutes": 60},
        "requires_qualification": True,
        "min_access_points": 500,
        "description": "Mechanic boss. Punishes chaos, rewards discipline. Verdict markers, execution zones.",
        "lore": "It has no name because names imply mercy. It has none.",
        "phases": [
            _phase(1, 1.00, "Inquisition",
                   {"damage_mult": 1.0, "verdict_stacks": 1},
                   ["judgment_strike", "mark_of_guilt"]),
            _phase(2, 0.65, "Trial of the Damned",
                   {"damage_mult": 1.40, "verdict_stacks": 2, "zone_punishment": True},
                   ["sentence", "execution_zone", "law_wave"]),
            _phase(3, 0.35, "Absolute Verdict",
                   {"damage_mult": 1.75, "verdict_stacks": 3, "mirror_penalty": True},
                   ["mass_sentence", "chaos_punishment", "verdict_storm"],
                   {"verdict_zones": True}),
            _phase(4, 0.10, "Final Judgment",
                   {"damage_mult": 2.50, "instant_verdict": True},
                   ["oblivion_gavel", "universal_sentence", "erasure"],
                   {"all_punished": True, "mercy_window": 3}),
        ],
        "drops": [
            _drop("Seal of Verdict",         U, PER, "core",      0.55, 1, 1, is_guaranteed=True),
            _drop("Law Fragment",            R, PER, "material",  0.42, 1, 2),
            _drop("Punishment Crystal",      E, CLN, "material",  0.28, 1, 1),
            _drop("Judge Frame Set Recipe",  E, CLN, "recipe",    0.16,
                  recipe_code="judge_frame_set"),
            _drop("Unique Aura — Judge's Gaze", L, WGT, "ultra_rare", 0.05,
                  artifact_code="judges_gaze_aura"),
        ],
    },

    # ── 9. Firstborn Apex (monthly) ───────────────────────────────────────────
    {
        "code":      "firstborn_apex",
        "name":      "Firstborn Apex",
        "category":  "monthly",
        "archetype": "apex",
        "max_clans":  5,
        "max_heroes": 25,
        "num_phases": 5,
        "base_level": 25,
        "base_hp":    500000,
        "base_armor": 0.40,
        "base_damage": 4500,
        "base_speed":  1.40,
        "base_xp":     50000,
        "spawn_config": {"interval_hours": 720, "window_minutes": 120},  # monthly
        "requires_qualification": True,
        "min_access_points": 2000,
        "description": "The apex monthly boss. 5 phases, arena transforms, adapts to the raid. All archetypes.",
        "lore": "It existed before the first hero drew breath. It will exist after the last one falls.",
        "phases": [
            _phase(1, 1.00, "Primordial Awakening",
                   {"damage_mult": 1.0},
                   ["apex_slam", "origin_wave"]),
            _phase(2, 0.75, "Adaptive Fury — Tank",
                   {"damage_mult": 1.30, "armor_mult": 1.60},
                   ["colossus_form", "seismic_burst", "stone_aegis"],
                   {"terrain_raises": True}),
            _phase(3, 0.50, "Adaptive Fury — Swarm",
                   {"damage_mult": 1.50, "summon_apex_drones": True},
                   ["hive_mind_strike", "apex_drone_rush", "queen_echo"],
                   {"minion_wave": True}),
            _phase(4, 0.25, "Adaptive Fury — Storm",
                   {"damage_mult": 1.80, "aoe_fields": 8},
                   ["tempest_apex", "lightning_cage", "omega_storm"],
                   {"lightning_everywhere": True, "safe_zones": 1}),
            _phase(5, 0.08, "Firstborn Protocol",
                   {"damage_mult": 2.80, "enrage": True, "adapt": True},
                   ["genesis_collapse", "apex_erase", "firstborn_roar"],
                   {"arena_transforms": True, "chaos_mode": True}),
        ],
        "drops": [
            _drop("Apex Core",             E, PER, "core",       0.50, 1, 1, is_guaranteed=True),
            _drop("Primordial Essence",     E, PER, "material",  0.45, 1, 1, is_guaranteed=True),
            _drop("Legendary Neural Material", L, CLN, "material", 0.35, 1, 1),
            _drop("Apex Genesis Set Recipe",   L, CLN, "recipe",   0.20,
                  recipe_code="apex_genesis_set",
                  bonus_conditions=[{"condition": "no_deaths", "value": True, "bonus": 0.10}]),
            _drop("Mythic Artifact",        M, WGT, "ultra_rare", 0.03,
                  artifact_code="mythic_apex_artifact"),
            _drop("Server Title — Apex Slayer", L, WGT, "ultra_rare", 0.05,
                  artifact_code="title_apex_slayer",
                  bonus_conditions=[{"condition": "full_coalition", "value": True, "bonus": 0.02}]),
            _drop("Rare Rebirth Item",      L, WGT, "ultra_rare", 0.06,
                  artifact_code="rare_rebirth_token"),
        ],
    },
]

# Quick lookup helpers
BOSS_BY_CODE: Dict[str, Dict[str, Any]] = {b["code"]: b for b in BOSS_CATALOG}
BOSSES_BY_CATEGORY: Dict[str, List[Dict[str, Any]]] = {}
for _b in BOSS_CATALOG:
    BOSSES_BY_CATEGORY.setdefault(_b["category"], []).append(_b)


def get_boss(code: str) -> Dict[str, Any]:
    if code not in BOSS_BY_CODE:
        raise KeyError(f"Unknown boss code: {code!r}")
    return BOSS_BY_CODE[code]
