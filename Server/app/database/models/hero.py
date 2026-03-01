from sqlalchemy import Column, Integer, String, ForeignKey, UniqueConstraint, Boolean, DateTime, Numeric, CheckConstraint, Index
from sqlalchemy.orm import relationship
from app.database.base import Base, SoftDeleteMixin
from datetime import datetime
from decimal import Decimal

class Hero(SoftDeleteMixin, Base):
    __tablename__ = "heroes"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    generation = Column(Integer, nullable=False, default=1)
    nickname = Column(String(100), nullable=False, default="")
    strength = Column(Integer, nullable=False, default=0)
    agility = Column(Integer, nullable=False, default=0)
    intelligence = Column(Integer, nullable=True, default=0)
    endurance = Column(Integer, nullable=False, default=0)
    speed = Column(Integer, nullable=False, default=0)
    health = Column(Integer, nullable=False, default=0)
    defense = Column(Integer, nullable=False, default=0)
    luck = Column(Integer, nullable=False, default=0)
    field_of_view = Column(Integer, nullable=False, default=0)
    gold = Column(Numeric(12, 2), default=Decimal('0.00'))
    level = Column(Integer, nullable=False, default=1)
    experience = Column(Integer, nullable=False, default=0)
    is_training = Column(Boolean, default=False)
    training_end_time = Column(DateTime, nullable=True)
    locale = Column(String(5), nullable=False, default="en")
    owner_id = Column(Integer, ForeignKey("users.id"), index=True)
    owner = relationship("User", back_populates="heroes")
    perks = relationship("HeroPerk", back_populates="hero", cascade="all, delete-orphan")
    # is_deleted and deleted_at provided by SoftDeleteMixin
    equipment_items = relationship("Equipment", back_populates="hero", cascade="all, delete-orphan")
    is_dead = Column(Boolean, default=False)
    dead_until = Column(DateTime, nullable=True)
    is_on_auction = Column(Boolean, default=False)
    __table_args__ = (
        CheckConstraint('gold >= 0', name='ck_hero_gold_non_negative'),
        Index('ix_heroes_owner_deleted', 'owner_id', 'is_deleted'),
    )

class HeroPerk(Base):
    __tablename__ = "hero_perks"
    id = Column(Integer, primary_key=True)
    hero_id = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"))
    perk_id = Column(Integer, ForeignKey("perks.id"), nullable=True)
    perk_name = Column(String, nullable=True)
    perk_level = Column(Integer, nullable=False)
    hero = relationship("app.database.models.hero.Hero", back_populates="perks")
    perk = relationship("Perk")
    __table_args__ = (UniqueConstraint('hero_id', 'perk_id', name='_hero_perk_uc'),) 