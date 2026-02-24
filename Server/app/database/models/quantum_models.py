from sqlalchemy import (
    Column,
    Integer,
    String,
    ForeignKey,
    CheckConstraint,
    Float,
    JSON,
    DateTime,
    func,
)
from sqlalchemy.orm import relationship, Session
from app.database.base import Base
import random


class Hero(Base):
    __tablename__ = "quantum_heroes"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    level = Column(Integer, nullable=False, default=1)
    quantum_crafting_skill = Column(Integer, nullable=False, default=0)

    # relationships
    crafted_items = relationship("CraftedItem", back_populates="hero", cascade="all, delete-orphan")

    def has_resources(self, resources_needed: dict, available_resources: dict) -> bool:
        """Return True if available_resources contains at least the amounts specified in resources_needed."""
        for name, qty in resources_needed.items():
            if available_resources.get(name, 0) < qty:
                return False
        return True


class Equipment(Base):
    __tablename__ = "quantum_equipment"
    id = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("quantum_heroes.id"), nullable=False)
    slot = Column(String, nullable=False)
    stability = Column(Integer, nullable=False, default=0)
    energy = Column(Integer, nullable=False, default=0)
    durability = Column(Integer, nullable=False, default=0)
    mutation_chance = Column(Float, nullable=False, default=0.0)

    hero = relationship("Hero", back_populates="equipment_items")

    def apply_quantum_effect(self, effect: "QuantumEffect"):
        """Apply an instance of a quantum effect to this equipment."""
        effect.apply(self)

    def to_dict(self) -> dict:
        """Return a JSON-serializable representation for Godot client."""
        data = {
            "slot": self.slot,
            "stability": self.stability,
            "energy": self.energy,
            "durability": self.durability,
            "mutation_chance": self.mutation_chance,
        }
        # if the equipment has any recorded effects, assume we store them
        if hasattr(self, "effects"):
            data["effects"] = [eff.to_dict() for eff in self.effects]
        else:
            data["effects"] = []
        return data


class Resource(Base):
    __tablename__ = "quantum_resources"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    quantity = Column(Integer, nullable=False, default=0)
    __table_args__ = (
        CheckConstraint(
            "name IN ('Quantum Dust','Cosmic Alloy','Photon Shard','Nano Gel')",
            name="ck_resource_name",
        ),
    )


class Recipe(Base):
    __tablename__ = "quantum_recipes"
    id = Column(Integer, primary_key=True, index=True)
    output_slot = Column(String, nullable=False)
    required_resources = Column(JSON, nullable=False)  # store as {resource_name: qty}
    mutation_chance = Column(Float, nullable=False, default=0.0)

    def can_craft(self, available_resources: dict) -> bool:
        """Check whether recipe can be crafted with available_resources dict."""
        for name, qty in self.required_resources.items():
            if available_resources.get(name, 0) < qty:
                return False
        return True


class CraftedItem(Base):
    __tablename__ = "quantum_crafted_items"
    id = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("quantum_heroes.id"), nullable=False)
    equipment_id = Column(Integer, ForeignKey("quantum_equipment.id"), nullable=False)
    created_at = Column(DateTime, default=func.now())

    hero = relationship("Hero", back_populates="crafted_items")
    equipment = relationship("Equipment")


class QuantumEffect:
    """Represents an effect that can be applied to equipment."""

    def __init__(self, name: str):
        self.name = name
        # define simple defaults for strength/duration; could be extended
        if name == "Photon Surge":
            self.strength = 10
            self.duration = 5
        elif name == "Quantum Shield":
            self.strength = 5
            self.duration = 10
        elif name == "Temporal Boost":
            self.strength = 15
            self.duration = 3
        else:
            raise ValueError(f"Unknown effect: {name}")

    def apply(self, equipment: Equipment):
        """Modify equipment attributes based on the effect."""
        if self.name == "Photon Surge":
            equipment.energy += self.strength
        elif self.name == "Quantum Shield":
            equipment.stability += self.strength
        elif self.name == "Temporal Boost":
            equipment.durability += self.strength
        else:
            raise ValueError(f"Unknown effect: {self.name}")

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "strength": self.strength,
            "duration": self.duration,
        }


def craft_item(session: Session, hero: Hero, recipe: Recipe, resources: dict) -> Equipment:
    """Attempt to craft an item for *hero* using *recipe*.

    *session* is an active SQLAlchemy Session that will be used to persist
    changes. *resources* should be a mapping from resource name to a
    ``Resource`` instance representing the available stock.

    The function will:
    1. verify the hero has the minimal crafting skill (simple check here)
    2. make sure the provided resources cover the recipe requirements
    3. deduct the consumed quantities
    4. create an ``Equipment`` object and potentially apply a random
       ``QuantumEffect`` based on the recipe's mutation chance
    5. record a ``CraftedItem`` entry and commit all changes

    Returns the newly-created ``Equipment`` instance.
    """

    # basic skill requirement; adjust logic as needed for your game rules
    if hero.quantum_crafting_skill < 1:
        raise ValueError("Hero lacks the quantum crafting skill needed to craft anything.")

    # convert resources to a simple dict for checking
    available = {name: res.quantity for name, res in resources.items()}
    if not recipe.can_craft(available):
        raise ValueError("Insufficient resources to craft the recipe.")

    # deduct consumed materials
    for name, qty in recipe.required_resources.items():
        res = resources.get(name)
        if res is None:
            # should not happen because can_craft already checked
            continue
        res.quantity -= qty
        session.add(res)

    # create the equipment record
    eq = Equipment(
        hero_id=hero.id,
        slot=recipe.output_slot,
        stability=0,
        energy=0,
        durability=0,
        mutation_chance=recipe.mutation_chance,
    )
    session.add(eq)
    session.flush()  # populate eq.id

    # possibly mutate the item
    if recipe.mutation_chance and random.random() < recipe.mutation_chance:
        effect_name = random.choice(["Photon Surge", "Quantum Shield", "Temporal Boost"])
        effect = QuantumEffect(effect_name)
        eq.apply_quantum_effect(effect)

    # record the crafting transaction
    ci = CraftedItem(hero_id=hero.id, equipment_id=eq.id)
    session.add(ci)

    session.commit()
    return eq
