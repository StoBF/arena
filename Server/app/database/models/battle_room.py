"""
Tactical battle-planning room system.

Flow:
  1. POST /battle/room/create  → BattleRoom (status=waiting)
  2. POST /battle/room/join    → sets team_b_ids, status=planning
  3. WS  /ws/battle/{room_id} → real-time order sync
  4. POST /battle/room/order   → HeroOrder upsert
  5. POST /battle/room/ready   → player marks ready; auto-simulate when all ready
  6. GET  /battle/room/{id}/result → BattleResult

Stances: attack | defense | control | support | intercept | reserve
"""
from __future__ import annotations

import enum
from datetime import datetime

from sqlalchemy import (
    Column, Integer, String, JSON, DateTime, Boolean,
    ForeignKey, Enum as SAEnum, Text, UniqueConstraint
)
from sqlalchemy.orm import relationship

from app.database.base import Base


class BattleRoomStatus(str, enum.Enum):
    waiting   = "waiting"
    planning  = "planning"
    simulating = "simulating"
    completed = "completed"
    cancelled = "cancelled"


class HeroStance(str, enum.Enum):
    attack    = "attack"
    defense   = "defense"
    control   = "control"
    support   = "support"
    intercept = "intercept"
    reserve   = "reserve"


class BattleRoom(Base):
    """
    A tactical battle room that holds two teams and their pre-battle plans.
    """
    __tablename__ = "battle_rooms"

    id              = Column(Integer, primary_key=True, index=True)
    creator_id      = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    status          = Column(SAEnum(BattleRoomStatus, name="battle_room_status"),
                             nullable=False, default=BattleRoomStatus.waiting)

    # Team A = creator's side, Team B = opponent's side
    team_a_ids      = Column(JSON, nullable=False, default=list)   # [user_id, ...]
    team_b_ids      = Column(JSON, nullable=False, default=list)

    # Shared team directives (set by each team captain)
    team_a_directives = Column(JSON, nullable=False, default=dict)
    team_b_directives = Column(JSON, nullable=False, default=dict)

    # Which users have pressed "ready"
    ready_a         = Column(JSON, nullable=False, default=list)   # [user_id, ...]
    ready_b         = Column(JSON, nullable=False, default=list)

    created_at      = Column(DateTime, default=datetime.utcnow, nullable=False)
    started_at      = Column(DateTime, nullable=True)
    finished_at     = Column(DateTime, nullable=True)

    orders          = relationship("HeroOrder", back_populates="room",
                                   cascade="all, delete-orphan")
    result          = relationship("BattleResult", back_populates="room",
                                   uselist=False, cascade="all, delete-orphan")


class HeroOrder(Base):
    """
    Tactical order assigned to a single hero before battle.
    Each player sets one order per hero they control.
    """
    __tablename__ = "hero_orders"

    id               = Column(Integer, primary_key=True, index=True)
    room_id          = Column(Integer, ForeignKey("battle_rooms.id", ondelete="CASCADE"),
                               nullable=False, index=True)
    user_id          = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    hero_id          = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"), nullable=False)

    # Tactical plan
    stance           = Column(SAEnum(HeroStance, name="hero_stance"),
                               nullable=False, default=HeroStance.attack)
    primary_action   = Column(String(64),  nullable=False, default="basic_attack")
    primary_target   = Column(String(128), nullable=True)   # hero_id or targeting rule
    fallback_rule    = Column(String(256), nullable=True)
    reactive_trigger = Column(String(256), nullable=True)

    room  = relationship("BattleRoom", back_populates="orders")


class BattleResult(Base):
    """
    Outcome of a simulated battle room.
    Rewards JSON holds per-player distributions.
    """
    __tablename__ = "battle_results"

    id             = Column(Integer, primary_key=True, index=True)
    room_id        = Column(Integer, ForeignKey("battle_rooms.id", ondelete="CASCADE"),
                             nullable=False, unique=True)

    winner_team    = Column(String(8), nullable=True)    # "a" | "b" | "draw"
    battle_log     = Column(JSON, nullable=False, default=list)
    rewards        = Column(JSON, nullable=False, default=dict)   # {user_id: {currency, resources}}
    created_at     = Column(DateTime, default=datetime.utcnow, nullable=False)

    room = relationship("BattleRoom", back_populates="result")


class PlayerResourceInventory(Base):
    """
    Tracks how many units of each GameResource a player owns.
    """
    __tablename__ = "player_resource_inventory"

    id          = Column(Integer, primary_key=True, index=True)
    user_id     = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    resource_id = Column(Integer, ForeignKey("resources.id"), nullable=False)
    quantity    = Column(Integer, nullable=False, default=0)

    resource    = relationship("GameResource")

    __table_args__ = (
        UniqueConstraint("user_id", "resource_id", name="uq_player_resource_inv"),
    )
