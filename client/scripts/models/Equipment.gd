extends Resource
class_name Equipment

# Resource representing a piece of equippable gear

@export var slot: String = ""  # Helmet, Armor, Gloves, Boots, Quantum Module
@export var stability: int = 0
@export var energy: int = 0
@export var durability: int = 0
@export var mutation_chance: float = 0.0
@export var skill_requirement: int = 0

# optional visual representation
@export var icon: Texture2D
@export var model: PackedScene

# effects list (each element should be a QuantumEffect or dictionary)
var quantum_effects: Array = []

func to_dict() -> Dictionary:
    return {
        "slot": slot,
        "stability": stability,
        "energy": energy,
        "durability": durability,
        "mutation_chance": mutation_chance,
        "skill_requirement": skill_requirement,
        "quantum_effects": quantum_effects,
    }
