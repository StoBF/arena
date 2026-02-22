from sqlalchemy import Column, Integer, String, Float, ForeignKey
from sqlalchemy.orm import relationship
from app.database.models.models import Base

class RaidBoss(Base):
    __tablename__ = "raid_bosses"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    gen_min = Column(Integer, nullable=False)
    gen_max = Column(Integer, nullable=False)
    loot_table = relationship("RaidDropItem", back_populates="boss", cascade="all, delete-orphan")
    drop_recipes = relationship("RecipeDrop", back_populates="boss", cascade="all, delete-orphan")
    recipes = relationship("CraftRecipe", back_populates="boss")

class RaidDropItem(Base):
    __tablename__ = "raid_drops"
    id = Column(Integer, primary_key=True)
    boss_id = Column(Integer, ForeignKey("raid_bosses.id"))
    item_id = Column(Integer, ForeignKey("items.id"), nullable=False)
    chance = Column(Float, nullable=False)
    boss = relationship("RaidBoss", back_populates="loot_table")
    item = relationship("Item")

class RecipeDrop(Base):
    __tablename__ = "recipe_drops"
    id = Column(Integer, primary_key=True)
    boss_id = Column(Integer, ForeignKey("raid_bosses.id"))
    recipe_id = Column(Integer, ForeignKey("craft_recipes.id"), nullable=False)
    chance = Column(Float, nullable=False)
    boss = relationship("RaidBoss", back_populates="drop_recipes")
    recipe = relationship("CraftRecipe") 