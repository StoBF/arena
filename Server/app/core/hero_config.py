BASE_SUCCESS_RATES = {1: 1.0, 2: 0.90, 3: 0.75, 4: 0.50, 5: 0.25, 6: 0.10, 7: 0.05, 8: 0.02, 9: 0.01, 10: 0.005}
MAX_BONUS_FACTOR = 0.5  # 50% of base
MAX_HEROES = 5

# ---------------------------------------------------------------------------
# Primary stats: S.P.E.I.A.L.W
# (strength, perception, endurance, intelligence, agility, luck, willpower)
#
# speed, health, defense and field_of_view are now DERIVED stats —
# see app.core.derived_stats for the formulas.
# ---------------------------------------------------------------------------

PRIMARY_STATS = ["strength", "perception", "endurance", "intelligence", "agility", "luck", "willpower"]

ATTRIBUTE_RANGES = {
    1:  {"strength": (5, 10),  "perception": (5, 10),  "endurance": (5, 10),  "intelligence": (5, 10),  "agility": (5, 10),  "luck": (1, 5),   "willpower": (3, 8)},
    2:  {"strength": (8, 15),  "perception": (8, 15),  "endurance": (8, 15),  "intelligence": (8, 15),  "agility": (8, 15),  "luck": (2, 7),   "willpower": (5, 12)},
    3:  {"strength": (12, 20), "perception": (12, 20), "endurance": (12, 20), "intelligence": (12, 20), "agility": (12, 20), "luck": (3, 9),   "willpower": (8, 16)},
    4:  {"strength": (18, 30), "perception": (18, 30), "endurance": (18, 30), "intelligence": (18, 30), "agility": (18, 30), "luck": (4, 12),  "willpower": (12, 24)},
    5:  {"strength": (25, 50), "perception": (25, 50), "endurance": (25, 50), "intelligence": (25, 50), "agility": (25, 50), "luck": (5, 15),  "willpower": (18, 38)},
    6:  {"strength": (35, 60), "perception": (35, 60), "endurance": (35, 60), "intelligence": (35, 60), "agility": (35, 60), "luck": (7, 18),  "willpower": (25, 48)},
    7:  {"strength": (45, 70), "perception": (45, 70), "endurance": (45, 70), "intelligence": (45, 70), "agility": (45, 70), "luck": (9, 21),  "willpower": (33, 58)},
    8:  {"strength": (55, 80), "perception": (55, 80), "endurance": (55, 80), "intelligence": (55, 80), "agility": (55, 80), "luck": (11, 24), "willpower": (42, 68)},
    9:  {"strength": (65, 90), "perception": (65, 90), "endurance": (65, 90), "intelligence": (65, 90), "agility": (65, 90), "luck": (13, 27), "willpower": (52, 78)},
    10: {"strength": (80, 100),"perception": (80, 100),"endurance": (80, 100),"intelligence": (80, 100),"agility": (80, 100),"luck": (15, 30), "willpower": (65, 90)},
}

# ---------------------------------------------------------------------------
# Archetype configuration
# ---------------------------------------------------------------------------
# Each archetype has stat growth weights (multiplied by a small bonus during
# generation) and a list of ability domains it has affinity with.

ARCHETYPE_STAT_WEIGHTS = {
    "VANGUARD":  {"strength": 1.3, "perception": 0.9, "endurance": 1.2, "intelligence": 0.8, "agility": 0.9, "luck": 0.9, "willpower": 1.1},
    "PREDATOR":  {"strength": 1.1, "perception": 1.2, "endurance": 0.9, "intelligence": 0.9, "agility": 1.3, "luck": 1.0, "willpower": 0.8},
    "PHANTOM":   {"strength": 0.8, "perception": 1.3, "endurance": 0.8, "intelligence": 1.0, "agility": 1.3, "luck": 1.1, "willpower": 0.9},
    "MYSTIC":    {"strength": 0.7, "perception": 1.0, "endurance": 0.8, "intelligence": 1.4, "agility": 0.8, "luck": 1.0, "willpower": 1.3},
    "WARDEN":    {"strength": 1.1, "perception": 0.9, "endurance": 1.4, "intelligence": 0.9, "agility": 0.7, "luck": 0.9, "willpower": 1.2},
    "APOSTLE":   {"strength": 0.8, "perception": 1.0, "endurance": 1.0, "intelligence": 1.2, "agility": 0.9, "luck": 1.1, "willpower": 1.3},
    "CHIMERA":   {"strength": 1.1, "perception": 1.1, "endurance": 1.0, "intelligence": 1.0, "agility": 1.0, "luck": 1.1, "willpower": 1.0},
}

ARCHETYPE_ABILITY_AFFINITY = {
    "VANGUARD":  ["ORDER", "ELEMENTAL"],
    "PREDATOR":  ["BLOOD", "BIOMORPH"],
    "PHANTOM":   ["SHADOW", "PSIONIC"],
    "MYSTIC":    ["PSIONIC", "SPACE"],
    "WARDEN":    ["ORDER", "BIOMORPH"],
    "APOSTLE":   ["BLOOD", "CHAOS"],
    "CHIMERA":   ["CHAOS", "BIOMORPH", "SHADOW"],
}

# ---------------------------------------------------------------------------
# Starter abilities per archetype (granted at generation)
# ---------------------------------------------------------------------------

ARCHETYPE_STARTER_ABILITIES = {
    "VANGUARD": {
        "ability_code": "shield_wall",
        "ability_name": "Shield Wall",
        "ability_type": "DEFENSIVE",
        "ability_domain": "ORDER",
    },
    "PREDATOR": {
        "ability_code": "predatory_assimilation",
        "ability_name": "Predatory Assimilation",
        "ability_type": "MUTATION",
        "ability_domain": "BIOMORPH",
    },
    "PHANTOM": {
        "ability_code": "shadow_step",
        "ability_name": "Shadow Step",
        "ability_type": "UTILITY",
        "ability_domain": "SHADOW",
    },
    "MYSTIC": {
        "ability_code": "mind_lance",
        "ability_name": "Mind Lance",
        "ability_type": "OFFENSIVE",
        "ability_domain": "PSIONIC",
    },
    "WARDEN": {
        "ability_code": "fortify",
        "ability_name": "Fortify",
        "ability_type": "DEFENSIVE",
        "ability_domain": "ORDER",
    },
    "APOSTLE": {
        "ability_code": "blood_pact",
        "ability_name": "Blood Pact",
        "ability_type": "SUPPORT",
        "ability_domain": "BLOOD",
    },
    "CHIMERA": {
        "ability_code": "volatile_mutation",
        "ability_name": "Volatile Mutation",
        "ability_type": "MUTATION",
        "ability_domain": "CHAOS",
    },
}

# ---------------------------------------------------------------------------
# Body part defaults (Fallout-style body damage system)
# ---------------------------------------------------------------------------
# max_hp values are base defaults; future scaling can factor in endurance/level.

BODY_PARTS = [
    {"part_name": "head",      "max_hp": 40,  "armor": 0},
    {"part_name": "torso",     "max_hp": 80,  "armor": 0},
    {"part_name": "left_arm",  "max_hp": 50,  "armor": 0},
    {"part_name": "right_arm", "max_hp": 50,  "armor": 0},
    {"part_name": "left_leg",  "max_hp": 55,  "armor": 0},
    {"part_name": "right_leg", "max_hp": 55,  "armor": 0},
]

# ---------------------------------------------------------------------------
# Training system
# ---------------------------------------------------------------------------
# time_minutes = base_time * (1 + level * 0.18) ^ 1.35

TRAINING_BASE_TIME = {
    "attribute":  15,   # minutes – base for stat training
    "discipline": 30,   # minutes – base for discipline training
    "ability":    45,   # minutes – base for ability training
}

TRAINING_MAX_QUEUE_SLOTS = 3   # max simultaneous training entries per hero

# Disciplines: code → display name + short description
DISCIPLINES = {
    "iron_body":          {"name": "Iron Body",          "desc": "Increases endurance and damage resistance"},
    "predator_vision":    {"name": "Predator Vision",    "desc": "Sharpens perception and critical targeting"},
    "shadow_motion":      {"name": "Shadow Motion",      "desc": "Improves evasion and stealth capability"},
    "mind_forge":         {"name": "Mind Forge",         "desc": "Strengthens willpower and psionic resistance"},
    "last_stand":         {"name": "Last Stand",         "desc": "Boosts survival at critical health thresholds"},
    "elemental_harmony":  {"name": "Elemental Harmony",  "desc": "Balances elemental affinity and recovery"},
}

# ---------------------------------------------------------------------------
# Hero titles — earned automatically when thresholds are met
# ---------------------------------------------------------------------------
# Each entry: code → {name, condition_field, threshold, source_label}

HERO_TITLES = {
    "the_slayer":       {"name": "The Slayer",       "field": "total_kills",  "threshold": 100, "source": "kills:100"},
    "arena_champion":   {"name": "Arena Champion",   "field": "arena_wins",   "threshold": 50,  "source": "arena_wins:50"},
    "dragon_killer":    {"name": "Dragon Killer",    "field": "boss_kills",   "threshold": 10,  "source": "boss_kills:10"},
    "the_survivor":     {"name": "The Survivor",     "field": "battles",      "threshold": 200, "source": "battles:200"},
    "bloodied":         {"name": "Bloodied",         "field": "damage_taken",  "threshold": 50000, "source": "damage_taken:50000"},
    "devastator":       {"name": "Devastator",       "field": "damage_dealt",  "threshold": 100000, "source": "damage_dealt:100000"},
}

# ---------------------------------------------------------------------------
# Resurrection system
# ---------------------------------------------------------------------------
# HP thresholds for hero condition (percentage of max_hp)
# condition is derived from current_hp / max_hp ratio
CONDITION_THRESHOLDS = [
    (0.75, "healthy"),           # >= 75%
    (0.50, "wounded"),           # >= 50%
    (0.25, "severely_injured"),  # >= 25%
    (0.01, "crippled"),          # >= 1%
    (0.00, "dead"),              # 0%
]

# Artifacts that can resurrect dead heroes
RESURRECTION_ARTIFACTS = {
    "phoenix_core": {
        "name": "Phoenix Core",
        "hp_restore_pct": 0.50,      # restore to 50% of max HP
        "condition_after": "wounded",
        "side_effects": [],           # clean revival
    },
    "heart_of_reversal": {
        "name": "Heart of Reversal",
        "hp_restore_pct": 0.25,      # restore to 25% of max HP
        "condition_after": "severely_injured",
        "side_effects": [
            {"type": "permanent_scar",       "desc": "A visible scar marks the hero's return from death"},
            {"type": "stat_reduction",       "desc": "One random primary stat permanently reduced by 1", "stat_penalty": 1},
            {"type": "mutation_instability", "desc": "Mutation abilities have a chance to misfire"},
        ],
    },
}

# Max resurrections before permadeath becomes irreversible
MAX_RESURRECTIONS = 3

# ---------------------------------------------------------------------------
# Perks (unchanged)
# ---------------------------------------------------------------------------

PERKS_LIST = [
    "Pilot", "Astrochemist", "Cyber Mage", "Quantum Hacker", "Starforged", "Voidwalker", "Mech Tamer", "Plasma Gunner",
    "Gravity Bender", "Nano Surgeon", "AI Whisperer", "Warp Specialist", "Shield Engineer", "Drone Commander", "Bioengineer",
    "Stellar Navigator", "Exosuit Expert", "Energy Siphon", "Cryo Specialist", "Pyro Technician", "EMP Saboteur", "Xeno Linguist",
    "Terraformer", "Astro Botanist", "Cosmic Oracle", "Dark Matter Adept", "Photon Bladesman", "Neural Enhancer", "Time Dilationist",
    "Antimatter Alchemist", "Singularity Monk", "Galactic Diplomat", "Space Pirate", "Starship Gunner", "Meteoric Defender",
    "Radiation Healer", "Wormhole Scout", "Celestial Bard", "Comet Rider", "Black Hole Warden", "Solar Flare", "Ion Gladiator",
    "Stasis Warlord", "Nebula Trickster", "Astro Gladiator", "Psycho Invoker", "Spectral Reaver", "Juggernaut", "Vanguard", "Trickster"
]

# ---------------------------------------------------------------------------
# Nickname map — updated with new primary stats
# ---------------------------------------------------------------------------

NICKNAME_MAP = {
    "en": {
        "strength": "the Mighty", "perception": "the Vigilant", "intelligence": "the Wise",
        "endurance": "the Unyielding", "agility": "the Swift", "luck": "the Fortunate",
        "willpower": "the Resolute",
        "Fire Mastery": "Flameheart", "Stealth": "Shadowstrider"
    },
    "pl": {
        "strength": "Potężny", "perception": "Czujny", "intelligence": "Mądry",
        "endurance": "Niezłomny", "agility": "Zwinny", "luck": "Szczęśliwy",
        "willpower": "Niezachwiany",
        "Fire Mastery": "Władca Ognia", "Stealth": "Cień"
    },
    "uk": {
        "strength": "Могутній", "perception": "Пильний", "intelligence": "Мудрий",
        "endurance": "Непохитний", "agility": "Швидкий", "luck": "Щасливий",
        "willpower": "Незламний",
        "Fire Mastery": "Повелитель вогню", "Stealth": "Тінь"
    }
}

LOCALE_MAP = {"en": "en_US", "pl": "pl_PL", "uk": "uk_UA"}

ALLOWED_SLOTS = [
    "weapon", "helmet", "spacesuit", "boots", "artifact", "visor", "force_field", "utility_belt", "gadget", "implant"
]

__table_args__ = {'extend_existing': True} 