"""
Armor item catalog + set-bonus definitions.

Slots  : helmet, chest, legs, gloves, boots, shoulders
Tiers  : 1-6  (T1 = starter, T6 = singularity end-game)
SetType: bastion | pulse | rift | siphon | predator | astral | null_set | bioform
"""
from __future__ import annotations

import enum
from sqlalchemy import (
    Column, Integer, String, Enum as SAEnum, JSON, Boolean, ForeignKey, Text,
    UniqueConstraint
)
from sqlalchemy.orm import relationship
from app.database.base import Base


class ArmorSlot(str, enum.Enum):
    helmet    = "helmet"
    chest     = "chest"
    legs      = "legs"
    gloves    = "gloves"
    boots     = "boots"
    shoulders = "shoulders"


class ArmorSetType(str, enum.Enum):
    bastion   = "bastion"
    pulse     = "pulse"
    rift      = "rift"
    siphon    = "siphon"
    predator  = "predator"
    astral    = "astral"
    null_set  = "null_set"
    bioform   = "bioform"


class ArmorTier(int, enum.Enum):
    t1 = 1
    t2 = 2
    t3 = 3
    t4 = 4
    t5 = 5
    t6 = 6


class ArmorItem(Base):
    """
    Catalog entry for a craftable / droppable armor piece.
    Actual instance ownership is tracked via PlayerArmorInventory.
    """
    __tablename__ = "armor_items"

    id          = Column(Integer, primary_key=True, index=True)
    name        = Column(String(128), nullable=False, unique=True)
    description = Column(Text, default="")
    slot        = Column(SAEnum(ArmorSlot,   name="armor_slot"),    nullable=False)
    tier        = Column(Integer,             nullable=False, default=1)
    set_type    = Column(SAEnum(ArmorSetType, name="armor_set_type"), nullable=False)
    is_starter  = Column(Boolean, default=False)

    # Stat bonuses stored as JSON for flexibility
    # keys: defense, stamina, willpower, speed, strength, agility, hp
    bonuses     = Column(JSON, nullable=False, default=dict)

    # Craft recipe that produces this piece (nullable → drop-only)
    recipe_id   = Column(Integer, ForeignKey("craft_recipes.id"), nullable=True)
    recipe      = relationship("CraftRecipe")

    instances   = relationship("PlayerArmorInventory", back_populates="armor_item")


class ArmorSetBonus(Base):
    """
    Threshold bonuses for equipping N pieces of the same set.
    One row per (set_type, pieces_required) combination — 2, 4, 6.
    """
    __tablename__ = "armor_set_bonuses"

    id              = Column(Integer, primary_key=True, index=True)
    set_type        = Column(SAEnum(ArmorSetType, name="armor_set_type"), nullable=False)
    pieces_required = Column(Integer, nullable=False)   # 2, 4 or 6
    bonuses         = Column(JSON, nullable=False, default=dict)
    description     = Column(String(256), default="")

    __table_args__ = (
        UniqueConstraint("set_type", "pieces_required", name="uq_set_bonus_type_pieces"),
    )


class PlayerArmorInventory(Base):
    """
    Tracks ownership of individual armor pieces.
    is_equipped=True means the piece is currently on the hero.
    """
    __tablename__ = "player_armor_inventory"

    id            = Column(Integer, primary_key=True, index=True)
    user_id       = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    hero_id       = Column(Integer, ForeignKey("heroes.id", ondelete="SET NULL"), nullable=True)
    armor_item_id = Column(Integer, ForeignKey("armor_items.id"), nullable=False)
    is_equipped   = Column(Boolean, default=False)
    quality       = Column(String(32), default="normal")   # normal | fine | superior | legendary
    extra_mods    = Column(JSON, default=dict)              # random roll modifiers

    armor_item    = relationship("ArmorItem", back_populates="instances")
