from sqlalchemy import Column, Integer, String, Float, Boolean, ForeignKey, DateTime, JSON
from sqlalchemy.orm import relationship
from app.database.base import Base
from datetime import datetime

class MobTemplate(Base):
    __tablename__ = "mob_templates"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    level = Column(Integer, nullable=False)
    base_stats = Column(JSON, nullable=False)  # dict: {"strength": 10, ...}
    is_boss = Column(Boolean, default=False)
    perks = relationship("MobPerk", back_populates="mob_template")

class BossPerk(Base):
    __tablename__ = "boss_perks"
    id = Column(Integer, primary_key=True)
    name = Column(String, nullable=False)
    description = Column(String)
    effect = Column(JSON)  # dict: {"type": "buff", "value": 10}

class MobPerk(Base):
    __tablename__ = "mob_perks"
    id = Column(Integer, primary_key=True)
    mob_template_id = Column(Integer, ForeignKey("mob_templates.id"), nullable=False)
    perk_id = Column(Integer, ForeignKey("boss_perks.id"), nullable=False)
    mob_template = relationship("MobTemplate", back_populates="perks")
    perk = relationship("BossPerk")

class RaidArenaInstance(Base):
    __tablename__ = "raid_arena_instances"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    # list of hero IDs participating in the raid
    team_ids = Column(JSON, nullable=False)
    boss_id = Column(Integer, ForeignKey("raid_bosses.id"), nullable=False)
    # pre-generated waves: list of waves, each wave is list of mob dicts
    waves = Column(JSON, default=list)
    current_wave = Column(Integer, default=1)
    status = Column(String, default="pending")  # pending|active|completed
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    # convenience property for duration or active check
    is_active = Column(Boolean, default=True)

class PvEBattleLog(Base):
    __tablename__ = "pve_battle_logs"
    id = Column(Integer, primary_key=True)
    instance_id = Column(Integer, ForeignKey("raid_arena_instances.id"), nullable=False)
    events = Column(JSON, nullable=False)  # turn-by-turn event payloads
    outcome = Column(String, nullable=False)  # "win" or "loss"
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False) 