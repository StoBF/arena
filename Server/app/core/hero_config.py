BASE_SUCCESS_RATES = {1: 1.0, 2: 0.90, 3: 0.75, 4: 0.50, 5: 0.25, 6: 0.10, 7: 0.05, 8: 0.02, 9: 0.01, 10: 0.005}
MAX_BONUS_FACTOR = 0.5  # 50% of base
MAX_HEROES = 5

ATTRIBUTE_RANGES = {
    1: {"strength": (5, 10), "agility": (5, 10), "intelligence": (5, 10), "endurance": (5, 10), "speed": (5, 10), "health": (30, 50), "defense": (2, 5), "luck": (1, 5), "field_of_view": (5, 10)},
    2: {"strength": (8, 15), "agility": (8, 15), "intelligence": (8, 15), "endurance": (8, 15), "speed": (8, 15), "health": (40, 65), "defense": (3, 7), "luck": (2, 7), "field_of_view": (8, 15)},
    3: {"strength": (12, 20), "agility": (12, 20), "intelligence": (12, 20), "endurance": (12, 20), "speed": (12, 20), "health": (55, 80), "defense": (5, 10), "luck": (3, 9), "field_of_view": (12, 20)},
    4: {"strength": (18, 30), "agility": (18, 30), "intelligence": (18, 30), "endurance": (18, 30), "speed": (18, 30), "health": (70, 110), "defense": (7, 14), "luck": (4, 12), "field_of_view": (18, 30)},
    5: {"strength": (25, 50), "agility": (25, 50), "intelligence": (25, 50), "endurance": (25, 50), "speed": (25, 50), "health": (100, 160), "defense": (10, 20), "luck": (5, 15), "field_of_view": (25, 50)},
    6: {"strength": (35, 60), "agility": (35, 60), "intelligence": (35, 60), "endurance": (35, 60), "speed": (35, 60), "health": (130, 200), "defense": (13, 25), "luck": (7, 18), "field_of_view": (35, 60)},
    7: {"strength": (45, 70), "agility": (45, 70), "intelligence": (45, 70), "endurance": (45, 70), "speed": (45, 70), "health": (160, 250), "defense": (16, 30), "luck": (9, 21), "field_of_view": (45, 70)},
    8: {"strength": (55, 80), "agility": (55, 80), "intelligence": (55, 80), "endurance": (55, 80), "speed": (55, 80), "health": (200, 320), "defense": (20, 36), "luck": (11, 24), "field_of_view": (55, 80)},
    9: {"strength": (65, 90), "agility": (65, 90), "intelligence": (65, 90), "endurance": (65, 90), "speed": (65, 90), "health": (250, 400), "defense": (25, 43), "luck": (13, 27), "field_of_view": (65, 90)},
    10: {"strength": (80, 100), "agility": (80, 100), "intelligence": (80, 100), "endurance": (80, 100), "speed": (80, 100), "health": (320, 500), "defense": (32, 50), "luck": (15, 30), "field_of_view": (80, 100)},
}

PERKS_LIST = [
    "Pilot", "Astrochemist", "Cyber Mage", "Quantum Hacker", "Starforged", "Voidwalker", "Mech Tamer", "Plasma Gunner",
    "Gravity Bender", "Nano Surgeon", "AI Whisperer", "Warp Specialist", "Shield Engineer", "Drone Commander", "Bioengineer",
    "Stellar Navigator", "Exosuit Expert", "Energy Siphon", "Cryo Specialist", "Pyro Technician", "EMP Saboteur", "Xeno Linguist",
    "Terraformer", "Astro Botanist", "Cosmic Oracle", "Dark Matter Adept", "Photon Bladesman", "Neural Enhancer", "Time Dilationist",
    "Antimatter Alchemist", "Singularity Monk", "Galactic Diplomat", "Space Pirate", "Starship Gunner", "Meteoric Defender",
    "Radiation Healer", "Wormhole Scout", "Celestial Bard", "Comet Rider", "Black Hole Warden", "Solar Flare", "Ion Gladiator",
    "Stasis Warlord", "Nebula Trickster", "Astro Gladiator", "Psycho Invoker", "Spectral Reaver", "Juggernaut", "Vanguard", "Trickster"
]

NICKNAME_MAP = {
    "en": {
        "strength": "the Mighty", "agility": "the Swift", "intelligence": "the Wise", "endurance": "the Unyielding",
        "speed": "the Rapid", "luck": "the Fortunate", "field_of_view": "the Watchful",
        "Fire Mastery": "Flameheart", "Stealth": "Shadowstrider"
    },
    "pl": {
        "strength": "Potężny", "agility": "Zwinny", "intelligence": "Mądry", "endurance": "Niezłomny",
        "speed": "Szybki", "luck": "Szczęśliwy", "field_of_view": "Czujny",
        "Fire Mastery": "Władca Ognia", "Stealth": "Cień"
    },
    "uk": {
        "strength": "Могутній", "agility": "Швидкий", "intelligence": "Мудрий", "endurance": "Непохитний",
        "speed": "Блискавичний", "luck": "Щасливий", "field_of_view": "Пильний",
        "Fire Mastery": "Повелитель вогню", "Stealth": "Тінь"
    }
}

LOCALE_MAP = {"en": "en_US", "pl": "pl_PL", "uk": "uk_UA"}

ALLOWED_SLOTS = [
    "weapon", "helmet", "spacesuit", "boots", "artifact", "visor", "force_field", "utility_belt", "gadget", "implant"
]

__table_args__ = {'extend_existing': True} 