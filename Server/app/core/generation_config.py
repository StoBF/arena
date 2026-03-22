"""
Generation configuration — single source of truth for hero generation.

Edit this file to rebalance the generation algorithm.
No generation logic lives here — this is pure data.
"""

from __future__ import annotations

# ═══════════════════════════════════════════════════════════════════
# 1. Layer success rates  (probability of passing each generation layer)
# ═══════════════════════════════════════════════════════════════════
#
# Layer 1 always succeeds.  Higher layers get progressively harder.
# A hero's "hero_generation_level" is the highest layer they passed.
# All 10 layers are always attempted; failures just mean that layer
# doesn't contribute upgrades.

LAYER_SUCCESS_RATES: dict[int, float] = {
    1:  1.0,       # 100 %
    2:  0.50,      #  50 %
    3:  0.25,      #  25 %
    4:  0.125,     #  12.5 %
    5:  0.0625,    #   6.25 %
    6:  0.03125,   #   3.125 %
    7:  0.02,      #   2 %
    8:  0.015,     #   1.5 %
    9:  0.0125,    #   1.25 %
    10: 0.01,      #   1 %
}

# Algorithm version — bump whenever generation logic changes
# so old heroes can be distinguished from new ones.
GENERATION_VERSION: int = 2


# ═══════════════════════════════════════════════════════════════════
# 2. Core stat configuration
# ═══════════════════════════════════════════════════════════════════

CORE_STATS: list[str] = [
    "health", "stamina", "defense", "vision",
    "speed", "agility", "luck", "willpower",
]

# Base stat range for layer 1 (before role weights).
# Each successful layer after 1 adds a LAYER_STAT_BONUS roll.
BASE_STAT_RANGE: dict[str, tuple[int, int]] = {
    "health":    (80, 130),
    "stamina":   (70, 120),
    "defense":   (5, 15),
    "vision":    (5, 15),
    "speed":     (5, 15),
    "agility":   (5, 15),
    "luck":      (1, 8),
    "willpower": (3, 10),
}

# Per-successful-layer bonus range added to base stats.
# Format: (min_pct_of_base, max_pct_of_base) — applied per stat.
# Example: a layer-2 success on health (base 100) with bonus (0.08, 0.18)
# adds 8-18 HP.
LAYER_STAT_BONUS_PCT: dict[str, tuple[float, float]] = {
    "health":    (0.08, 0.20),
    "stamina":   (0.06, 0.18),
    "defense":   (0.10, 0.25),
    "vision":    (0.08, 0.22),
    "speed":     (0.08, 0.22),
    "agility":   (0.08, 0.22),
    "luck":      (0.05, 0.15),
    "willpower": (0.06, 0.18),
}


# ═══════════════════════════════════════════════════════════════════
# 3. Hidden coefficient configuration
# ═══════════════════════════════════════════════════════════════════

COEFFICIENT_RANGES: dict[str, tuple[float, float]] = {
    "hero_coherence":         (0.55, 1.45),
    "stability":              (0.45, 1.55),
    "control_susceptibility": (0.25, 1.75),
    "transfer_conductivity":  (0.25, 1.75),
    "execution_resonance":    (0.40, 2.10),
    "affinity_bias":          (-1.0, 1.0),
}

# Extra range each successful layer adds (symmetrically).
# e.g. layer 3 success on hero_coherence with bump=0.04 means
# hero_coherence += uniform(-0.04, +0.04) (can shift either way).
COEFFICIENT_LAYER_BUMP: dict[str, float] = {
    "hero_coherence":         0.03,
    "stability":              0.04,
    "control_susceptibility": 0.03,
    "transfer_conductivity":  0.03,
    "execution_resonance":    0.05,
    "affinity_bias":          0.06,
}


# ═══════════════════════════════════════════════════════════════════
# 4. Role assignment weights
# ═══════════════════════════════════════════════════════════════════
#
# After full generation, score each role by:
#   score = Σ(stat_value × role_stat_weight)
#           + Σ(skill_family_count × role_skill_weight)
#           + Σ(coefficient × role_coeff_weight)
#
# Primary role = highest score.  Secondary = second-highest (if
# different and at least 60% of primary score).

ROLE_STAT_SCORING: dict[str, dict[str, float]] = {
    "VANGUARD":   {"health": 2.0, "stamina": 1.0, "defense": 2.0, "vision": 0.5, "speed": 0.5, "agility": 0.5, "luck": 0.5, "willpower": 1.5},
    "STRIKER":    {"health": 0.5, "stamina": 1.5, "defense": 0.5, "vision": 1.0, "speed": 1.5, "agility": 2.0, "luck": 1.0, "willpower": 0.5},
    "CONTROLLER": {"health": 0.5, "stamina": 1.0, "defense": 0.5, "vision": 2.0, "speed": 0.5, "agility": 1.0, "luck": 0.5, "willpower": 2.0},
    "SUPPORT":    {"health": 1.0, "stamina": 2.0, "defense": 0.5, "vision": 1.5, "speed": 0.5, "agility": 0.5, "luck": 1.0, "willpower": 1.5},
    "TRANSFER":   {"health": 0.5, "stamina": 1.5, "defense": 0.5, "vision": 1.0, "speed": 1.0, "agility": 1.0, "luck": 1.5, "willpower": 1.0},
}

ROLE_SKILL_SCORING: dict[str, dict[str, float]] = {
    "VANGUARD":   {"COMBAT": 3.0, "BUFF": 2.0, "DEBUFF": 0.5, "TRANSFER": 0.5, "CONTROL": 0.5},
    "STRIKER":    {"COMBAT": 3.0, "BUFF": 0.5, "DEBUFF": 2.0, "TRANSFER": 0.5, "CONTROL": 0.5},
    "CONTROLLER": {"COMBAT": 0.5, "BUFF": 0.5, "DEBUFF": 2.0, "TRANSFER": 1.0, "CONTROL": 3.0},
    "SUPPORT":    {"COMBAT": 0.5, "BUFF": 3.0, "DEBUFF": 0.5, "TRANSFER": 2.0, "CONTROL": 0.5},
    "TRANSFER":   {"COMBAT": 0.5, "BUFF": 1.0, "DEBUFF": 1.0, "TRANSFER": 3.0, "CONTROL": 2.0},
}

ROLE_COEFF_SCORING: dict[str, dict[str, float]] = {
    "VANGUARD":   {"stability": 3.0, "control_susceptibility": -1.0, "execution_resonance": 1.0},
    "STRIKER":    {"execution_resonance": 3.0, "stability": -0.5, "hero_coherence": 1.0},
    "CONTROLLER": {"control_susceptibility": -3.0, "hero_coherence": 2.0, "stability": 1.0},
    "SUPPORT":    {"hero_coherence": 3.0, "transfer_conductivity": 2.0, "stability": 1.0},
    "TRANSFER":   {"transfer_conductivity": 3.0, "execution_resonance": 2.0, "control_susceptibility": -1.0},
}

# Secondary role is assigned only if its score ≥ this fraction of primary.
SECONDARY_ROLE_MIN_RATIO: float = 0.60


# ═══════════════════════════════════════════════════════════════════
# 5. Skill generation pools
# ═══════════════════════════════════════════════════════════════════
#
# The full skills_catalog lives in the database.  At generation time
# the engine queries the catalog and filters by family.  The config
# below controls how MANY skills are granted per layer.

# Layer 1 always grants this many skills.
INITIAL_SKILL_COUNT: int = 2

# Each subsequent successful layer grants 0-1 new skills with this
# probability.
LAYER_NEW_SKILL_CHANCE: float = 0.50

# Chance that a successful layer upgrades an existing skill instead
# of granting a new one (when no new skill is granted).
LAYER_SKILL_UPGRADE_CHANCE: float = 0.70

# Maximum total skills a hero can have.
MAX_SKILLS: int = 8

# Families available per layer range.
# Layers 1-3: limited families.  4-7: more families.  8-10: all.
LAYER_FAMILY_UNLOCK: dict[int, list[str]] = {
    1: ["COMBAT", "BUFF"],
    2: ["COMBAT", "BUFF", "DEBUFF"],
    3: ["COMBAT", "BUFF", "DEBUFF"],
    4: ["COMBAT", "BUFF", "DEBUFF", "CONTROL"],
    5: ["COMBAT", "BUFF", "DEBUFF", "CONTROL", "TRANSFER"],
    6: ["COMBAT", "BUFF", "DEBUFF", "CONTROL", "TRANSFER"],
    7: ["COMBAT", "BUFF", "DEBUFF", "CONTROL", "TRANSFER"],
    8: ["COMBAT", "BUFF", "DEBUFF", "CONTROL", "TRANSFER"],
    9: ["COMBAT", "BUFF", "DEBUFF", "CONTROL", "TRANSFER"],
    10: ["COMBAT", "BUFF", "DEBUFF", "CONTROL", "TRANSFER"],
}

# Cost-generation-level improvement: successful layers may improve
# the stamina cost tier of existing skills.
LAYER_COST_IMPROVEMENT_CHANCE: float = 0.40

# Skill power scaling per generation level.
# power = power_base × SKILL_POWER_SCALE[gen_level]
SKILL_POWER_SCALE: dict[int, float] = {
    1: 1.0, 2: 1.15, 3: 1.35, 4: 1.60, 5: 1.90,
    6: 2.25, 7: 2.70, 8: 3.20, 9: 3.80, 10: 4.50,
}

# Stamina cost reduction per cost-generation-level.
# effective_cost = stamina_cost_base × SKILL_COST_SCALE[cost_gen_level]
SKILL_COST_SCALE: dict[int, float] = {
    1: 1.00, 2: 0.92, 3: 0.84, 4: 0.76, 5: 0.68,
    6: 0.60, 7: 0.54, 8: 0.48, 9: 0.43, 10: 0.38,
}


# ═══════════════════════════════════════════════════════════════════
# 6. Tag generation
# ═══════════════════════════════════════════════════════════════════

# Tags are granted at layer 1 and on some successful layers after.
INITIAL_TAG_COUNT: int = 2
LAYER_NEW_TAG_CHANCE: float = 0.35
MAX_TAGS: int = 10

TAG_POOLS: dict[str, list[str]] = {
    "personality": [
        "aggressive", "cautious", "reckless", "methodical",
        "stoic", "volatile", "cunning", "loyal", "ruthless",
        "patient", "impulsive", "calculating",
    ],
    "combat_style": [
        "brawler", "sniper", "flanker", "guardian",
        "berserker", "tactician", "assassin", "duelist",
        "skirmisher", "sentinel",
    ],
    "affinity": [
        "kinetic", "thermal", "psionic", "void",
        "bio", "electric", "gravity", "temporal",
    ],
}

# Weights for each group (higher = more likely to pick from that group).
TAG_GROUP_WEIGHTS: dict[str, float] = {
    "personality":  1.0,
    "combat_style": 1.2,
    "affinity":     0.8,
}


# ═══════════════════════════════════════════════════════════════════
# 7. Hidden trait generation
# ═══════════════════════════════════════════════════════════════════

HIDDEN_TRAIT_POOLS: list[str] = [
    "crit_affinity",
    "pain_threshold",
    "adrenaline_surge",
    "focus_depth",
    "resilience_factor",
    "aggression_index",
    "recovery_modifier",
    "sync_potential",
]

INITIAL_HIDDEN_TRAIT_COUNT: int = 2
LAYER_NEW_HIDDEN_TRAIT_CHANCE: float = 0.25
MAX_HIDDEN_TRAITS: int = 6

HIDDEN_TRAIT_RANGE: tuple[float, float] = (0.1, 1.5)
HIDDEN_TRAIT_LAYER_BUMP: tuple[float, float] = (-0.05, 0.10)


# ═══════════════════════════════════════════════════════════════════
# 8. Signature skill
# ═══════════════════════════════════════════════════════════════════

# A hero with generation level ≥ this threshold gets one skill
# marked as "is_signature = True".
SIGNATURE_SKILL_LAYER_THRESHOLD: int = 5
