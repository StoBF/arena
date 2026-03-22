"""
Hero configuration constants — v2 (role-based, skill catalog, no training/XP)

Sections
────────
1. Generation parameters       (success rates, max heroes)
2. Hero roles                   (5 base roles + stat/coefficient weights)
3. Core stats                   (hero_stats stat names + per-layer ranges)
4. Coefficient ranges           (hero-level hidden coefficients per generation layer)
5. Body parts                   (body damage model defaults)
6. Hero titles                  (achievement thresholds)
7. Condition / resurrection     (HP-based condition + artifacts)
8. Equipment                    (allowed gear slots)
9. Locale                       (i18n helpers)
"""

# ═══════════════════════════════════════════════════════════════════
# 1. Generation parameters
# ═══════════════════════════════════════════════════════════════════

BASE_SUCCESS_RATES = {
    1: 1.0,  2: 0.90, 3: 0.75, 4: 0.50, 5: 0.25,
    6: 0.10, 7: 0.05, 8: 0.02, 9: 0.01, 10: 0.005,
}
MAX_BONUS_FACTOR = 0.5   # 50 % of base
MAX_HEROES = 5
MAX_GENERATION_LAYERS = 10

# ═══════════════════════════════════════════════════════════════════
# 2. Hero roles
# ═══════════════════════════════════════════════════════════════════

HERO_ROLES = ["VANGUARD", "STRIKER", "CONTROLLER", "SUPPORT", "TRANSFER"]

# Stat growth weights per role (multiplied during generation stat roll).
# Keys match hero_stats columns.
ROLE_STAT_WEIGHTS = {
    "VANGUARD":   {"health": 1.4, "stamina": 1.1, "defense": 1.3, "vision": 0.8, "speed": 0.8, "agility": 0.9, "luck": 0.9, "willpower": 1.1},
    "STRIKER":    {"health": 1.0, "stamina": 1.2, "defense": 0.8, "vision": 1.1, "speed": 1.2, "agility": 1.3, "luck": 1.0, "willpower": 0.8},
    "CONTROLLER": {"health": 0.9, "stamina": 1.0, "defense": 0.9, "vision": 1.3, "speed": 0.9, "agility": 1.0, "luck": 1.0, "willpower": 1.3},
    "SUPPORT":    {"health": 1.1, "stamina": 1.3, "defense": 1.0, "vision": 1.1, "speed": 0.9, "agility": 0.8, "luck": 1.1, "willpower": 1.2},
    "TRANSFER":   {"health": 0.9, "stamina": 1.1, "defense": 0.8, "vision": 1.0, "speed": 1.1, "agility": 1.1, "luck": 1.1, "willpower": 1.0},
}

# Skill family affinities per role (used during skill selection at generation).
ROLE_SKILL_AFFINITY = {
    "VANGUARD":   ["COMBAT", "BUFF"],
    "STRIKER":    ["COMBAT", "DEBUFF"],
    "CONTROLLER": ["CONTROL", "DEBUFF"],
    "SUPPORT":    ["BUFF", "TRANSFER"],
    "TRANSFER":   ["TRANSFER", "CONTROL"],
}

# ═══════════════════════════════════════════════════════════════════
# 3. Core stats
# ═══════════════════════════════════════════════════════════════════

CORE_STATS = ["health", "stamina", "defense", "vision", "speed", "agility", "luck", "willpower"]

# Per-generation-layer stat ranges (before role weight multiplier).
STAT_RANGES = {
    1:  {"health": (80, 120),  "stamina": (80, 120),  "defense": (5, 12),   "vision": (5, 12),   "speed": (5, 12),   "agility": (5, 12),   "luck": (1, 5),   "willpower": (3, 8)},
    2:  {"health": (100, 150), "stamina": (100, 150), "defense": (8, 16),   "vision": (8, 16),   "speed": (8, 16),   "agility": (8, 16),   "luck": (2, 7),   "willpower": (5, 12)},
    3:  {"health": (130, 200), "stamina": (130, 190), "defense": (12, 22),  "vision": (12, 22),  "speed": (12, 22),  "agility": (12, 22),  "luck": (3, 9),   "willpower": (8, 16)},
    4:  {"health": (170, 260), "stamina": (160, 250), "defense": (18, 30),  "vision": (18, 30),  "speed": (18, 30),  "agility": (18, 30),  "luck": (4, 12),  "willpower": (12, 24)},
    5:  {"health": (220, 350), "stamina": (200, 330), "defense": (25, 42),  "vision": (25, 42),  "speed": (25, 42),  "agility": (25, 42),  "luck": (5, 15),  "willpower": (18, 38)},
    6:  {"health": (280, 440), "stamina": (250, 410), "defense": (33, 55),  "vision": (33, 55),  "speed": (33, 55),  "agility": (33, 55),  "luck": (7, 18),  "willpower": (25, 48)},
    7:  {"health": (350, 550), "stamina": (310, 510), "defense": (42, 68),  "vision": (42, 68),  "speed": (42, 68),  "agility": (42, 68),  "luck": (9, 21),  "willpower": (33, 58)},
    8:  {"health": (430, 670), "stamina": (380, 620), "defense": (52, 82),  "vision": (52, 82),  "speed": (52, 82),  "agility": (52, 82),  "luck": (11, 24), "willpower": (42, 68)},
    9:  {"health": (520, 800), "stamina": (460, 740), "defense": (63, 96),  "vision": (63, 96),  "speed": (63, 96),  "agility": (63, 96),  "luck": (13, 27), "willpower": (52, 78)},
    10: {"health": (620, 950), "stamina": (550, 880), "defense": (75, 110), "vision": (75, 110), "speed": (75, 110), "agility": (75, 110), "luck": (15, 30), "willpower": (65, 90)},
}

# ═══════════════════════════════════════════════════════════════════
# 4. Coefficient ranges  (hero-level hidden coefficients)
# ═══════════════════════════════════════════════════════════════════

# Rolled once during generation, influenced by role.
COEFFICIENT_DEFAULTS = {
    "hero_coherence":         {"min": 0.6, "max": 1.4},
    "stability":              {"min": 0.5, "max": 1.5},
    "control_susceptibility": {"min": 0.3, "max": 1.7},
    "transfer_conductivity":  {"min": 0.3, "max": 1.7},
    "execution_resonance":    {"min": 0.5, "max": 2.0},
    "affinity_bias":          {"min": -1.0, "max": 1.0},
}

# Per-role coefficient biases (added to the roll midpoint).
ROLE_COEFFICIENT_BIAS = {
    "VANGUARD":    {"stability": +0.15, "control_susceptibility": -0.10},
    "STRIKER":     {"execution_resonance": +0.20, "stability": -0.10},
    "CONTROLLER":  {"control_susceptibility": -0.25, "hero_coherence": +0.10},
    "SUPPORT":     {"hero_coherence": +0.15, "transfer_conductivity": +0.10},
    "TRANSFER":    {"transfer_conductivity": +0.25, "execution_resonance": +0.10},
}

# ═══════════════════════════════════════════════════════════════════
# 5. Body parts
# ═══════════════════════════════════════════════════════════════════

BODY_PARTS = [
    {"part_name": "head",      "max_hp": 40,  "armor": 0},
    {"part_name": "torso",     "max_hp": 80,  "armor": 0},
    {"part_name": "left_arm",  "max_hp": 50,  "armor": 0},
    {"part_name": "right_arm", "max_hp": 50,  "armor": 0},
    {"part_name": "left_leg",  "max_hp": 55,  "armor": 0},
    {"part_name": "right_leg", "max_hp": 55,  "armor": 0},
]

# ═══════════════════════════════════════════════════════════════════
# 6. Hero titles
# ═══════════════════════════════════════════════════════════════════

HERO_TITLES = {
    "the_slayer":     {"name": "The Slayer",     "field": "total_kills",   "threshold": 100,    "source": "kills:100"},
    "arena_champion": {"name": "Arena Champion", "field": "arena_wins",    "threshold": 50,     "source": "arena_wins:50"},
    "dragon_killer":  {"name": "Dragon Killer",  "field": "boss_kills",    "threshold": 10,     "source": "boss_kills:10"},
    "the_survivor":   {"name": "The Survivor",   "field": "battles",       "threshold": 200,    "source": "battles:200"},
    "bloodied":       {"name": "Bloodied",       "field": "damage_taken",  "threshold": 50000,  "source": "damage_taken:50000"},
    "devastator":     {"name": "Devastator",     "field": "damage_dealt",  "threshold": 100000, "source": "damage_dealt:100000"},
}

# ═══════════════════════════════════════════════════════════════════
# 7. Condition / resurrection
# ═══════════════════════════════════════════════════════════════════

CONDITION_THRESHOLDS = [
    (0.75, "healthy"),
    (0.50, "wounded"),
    (0.25, "severely_injured"),
    (0.01, "crippled"),
    (0.00, "dead"),
]

RESURRECTION_ARTIFACTS = {
    "phoenix_core": {
        "name": "Phoenix Core",
        "hp_restore_pct": 0.50,
        "condition_after": "wounded",
        "side_effects": [],
    },
    "heart_of_reversal": {
        "name": "Heart of Reversal",
        "hp_restore_pct": 0.25,
        "condition_after": "severely_injured",
        "side_effects": [
            {"type": "permanent_scar",       "desc": "A visible scar marks the hero's return from death"},
            {"type": "stat_reduction",       "desc": "One random core stat permanently reduced by 1", "stat_penalty": 1},
            {"type": "mutation_instability", "desc": "Skills have a small chance to misfire for 3 battles"},
        ],
    },
}

MAX_RESURRECTIONS = 3

# ═══════════════════════════════════════════════════════════════════
# 8. Equipment
# ═══════════════════════════════════════════════════════════════════

ALLOWED_SLOTS = [
    "weapon", "helmet", "spacesuit", "boots",
    "artifact", "visor", "force_field",
    "utility_belt", "gadget", "implant",
]

# ═══════════════════════════════════════════════════════════════════
# 9. Locale helpers
# ═══════════════════════════════════════════════════════════════════

LOCALE_MAP = {"en": "en_US", "pl": "pl_PL", "uk": "uk_UA"}