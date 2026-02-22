from sqlalchemy import Column, Integer, String, Float, Boolean, ForeignKey, DateTime, Enum
from sqlalchemy.orm import relationship
from app.database.models.raid_boss import RaidBoss
from app.database.models.models import Base
from datetime import datetime

class CraftRecipe(Base):
    __tablename__ = "craft_recipes"
    id = Column(Integer, primary_key=True)
    name = Column(String)
    item_type = Column(String, nullable=False)
    grade = Column(Integer)
    boss_id = Column(Integer, ForeignKey("raid_bosses.id"), nullable=True)
    drop_chance = Column(Float)
    craft_time_sec = Column(Integer)
    result_item_id = Column(Integer, ForeignKey("items.id"), nullable=True)
    resources = relationship("CraftRecipeResource", back_populates="recipe", cascade="all, delete-orphan")
    boss = relationship("RaidBoss", back_populates="recipes")

class CraftRecipeResource(Base):
    __tablename__ = "craft_recipe_resources"
    id = Column(Integer, primary_key=True)
    recipe_id = Column(Integer, ForeignKey("craft_recipes.id"), nullable=False)
    resource_id = Column(Integer, ForeignKey("resources.id"), nullable=False)
    quantity = Column(Integer, nullable=False)
    type = Column(String(8), nullable=False)  # 'pvp' або 'pve'
    recipe = relationship("CraftRecipe", back_populates="resources")
    resource = relationship("GameResource")

class CraftedItem(Base):
    __tablename__ = "crafted_items"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    result_item_id = Column(Integer, ForeignKey("items.id"), nullable=True)
    item_type = Column(String)
    grade = Column(Integer)
    is_mutated = Column(Boolean, default=False)
    recipe_id = Column(Integer, ForeignKey("craft_recipes.id"), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    item = relationship("Item")
    recipe = relationship("CraftRecipe")

class CraftQueue(Base):
    __tablename__ = "craft_queue"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer)
    recipe_id = Column(Integer)
    ready_at = Column(DateTime)