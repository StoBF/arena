"""
live_battle.py — SQLAlchemy persistence models for live battle sessions.

Active battle state lives in memory (see services/live_battle/runtime.py).
These tables store:
  - LiveBattleSession: outcome record (one row per completed battle)
  - LiveBattleEventLog: key events for replay / analytics
  - LiveBattleHeroResult: per-hero contribution summary
"""
from __future__ import annotations

import enum

from sqlalchemy import (
    BigInteger, Boolean, Column, DateTime, Enum as SAEnum,
    Float, ForeignKey, Index, Integer, JSON, String, Text,
)
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func

from app.database.base import Base


class BattleOutcome(str, enum.Enum):
    TEAM_A_WIN = "team_a_win"
    TEAM_B_WIN = "team_b_win"
    DRAW       = "draw"
    CANCELLED  = "cancelled"


class LiveBattleSession(Base):
    __tablename__ = "live_battle_sessions"
    __table_args__ = (
        Index("ix_lbs_status",    "status"),
        Index("ix_lbs_created",   "created_at"),
    )

    id           = Column(BigInteger, primary_key=True, autoincrement=True)
    battle_uuid  = Column(String(36), unique=True, nullable=False, index=True)
    map_id       = Column(String(64),  nullable=False, default="arena_skirmish")
    mode         = Column(String(16),  nullable=False, default="5v5")
    status       = Column(String(16),  nullable=False, default="pending")
    outcome      = Column(SAEnum(BattleOutcome, name="battle_outcome_enum"), nullable=True)
    winner_team  = Column(String(4),   nullable=True)

    team_a_user_ids = Column(JSON, nullable=False, default=list)
    team_b_user_ids = Column(JSON, nullable=False, default=list)

    total_ticks    = Column(Integer, nullable=False, default=0)
    elapsed_seconds = Column(Float,  nullable=False, default=0.0)

    created_at   = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    started_at   = Column(DateTime(timezone=True), nullable=True)
    finished_at  = Column(DateTime(timezone=True), nullable=True)

    events       = relationship("LiveBattleEventLog", back_populates="session",
                                cascade="all, delete-orphan")
    hero_results = relationship("LiveBattleHeroResult", back_populates="session",
                                cascade="all, delete-orphan")


class LiveBattleEventLog(Base):
    __tablename__ = "live_battle_event_logs"
    __table_args__ = (
        Index("ix_lbel_session",    "session_id"),
        Index("ix_lbel_tick",       "tick"),
        Index("ix_lbel_event_type", "event_type"),
    )

    id          = Column(BigInteger, primary_key=True, autoincrement=True)
    session_id  = Column(BigInteger, ForeignKey("live_battle_sessions.id",
                         ondelete="CASCADE"), nullable=False)
    tick        = Column(Integer,    nullable=False)
    event_type  = Column(String(32), nullable=False)
    source_hero_id = Column(Integer, nullable=True)
    target_hero_id = Column(Integer, nullable=True)
    position_x  = Column(Float,      nullable=True)
    position_z  = Column(Float,      nullable=True)
    payload     = Column(JSON,        nullable=False, default=dict)
    created_at  = Column(DateTime(timezone=True), server_default=func.now())

    session     = relationship("LiveBattleSession", back_populates="events")


class LiveBattleHeroResult(Base):
    __tablename__ = "live_battle_hero_results"
    __table_args__ = (
        Index("ix_lbhr_session", "session_id"),
        Index("ix_lbhr_user",    "user_id"),
    )

    id           = Column(BigInteger, primary_key=True, autoincrement=True)
    session_id   = Column(BigInteger, ForeignKey("live_battle_sessions.id",
                          ondelete="CASCADE"), nullable=False)
    hero_id      = Column(Integer,    nullable=False)
    user_id      = Column(Integer,    nullable=False)
    team_id      = Column(String(4),  nullable=False)
    primary_role = Column(String(16), nullable=False)

    damage_dealt    = Column(Float,   nullable=False, default=0.0)
    damage_taken    = Column(Float,   nullable=False, default=0.0)
    kills           = Column(Integer, nullable=False, default=0)
    control_seconds = Column(Float,   nullable=False, default=0.0)
    survived        = Column(Boolean, nullable=False, default=False)
    final_hp_pct    = Column(Float,   nullable=False, default=0.0)
    final_stamina_pct = Column(Float, nullable=False, default=0.0)

    session = relationship("LiveBattleSession", back_populates="hero_results")
