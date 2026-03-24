"""
Game Systems v2 — Hero Manager RPG
=====================================
DB models for 6 systems. Усі витрати — ТІЛЬКИ ігрова валюта (gold).
Стрічка конфігурації: config/game_config.yaml

  1. Daily Quest System    — DailyQuestTemplate, PlayerDailyQuest, PlayerStreak
  2. Battle Betting        — BettingMarket, MatchBet (parimutuel)
  3. Hero Healing          — HeroHealOrder (body-part timers, оплата gold)
  4. Resurrection Artifact — ResurrectionAttempt
  5. Currency Shop         — CurrencyPurchase (Stripe → gold)
  6. Alliance System       — Alliance, AllianceMember, AllianceWarChest
"""
from __future__ import annotations

import enum
from datetime import datetime

from sqlalchemy import (
    Boolean, Column, DateTime, Enum, Float,
    ForeignKey, Integer, JSON, Numeric, String, Text,
    UniqueConstraint, CheckConstraint,
)
from sqlalchemy.orm import relationship

from app.database.models.models import Base


# ══════════════════════════════════════════════════════════════════════════════
# 1. DAILY QUEST SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

class QuestCategory(str, enum.Enum):
    combat  = "combat"
    social  = "social"
    economy = "economy"
    raiding = "raiding"
    special = "special"


class QuestFrequency(str, enum.Enum):
    daily    = "daily"
    weekly   = "weekly"
    seasonal = "seasonal"


class DailyQuestTemplate(Base):
    """
    Definition of a reusable quest.
    task example: {"action": "win_battles", "target": 3}
    """
    __tablename__ = "daily_quest_templates"

    id          = Column(Integer, primary_key=True)
    code        = Column(String(64), unique=True, nullable=False)
    title       = Column(String(128), nullable=False)
    description = Column(Text, nullable=False)
    category    = Column(Enum(QuestCategory), nullable=False)
    frequency   = Column(Enum(QuestFrequency), nullable=False, default=QuestFrequency.daily)

    # {"action": "win_battles", "target": 3}
    task        = Column(JSON, nullable=False)

    # [{"type": "currency", "amount": 200}, {"type": "resource", "code": "steel_core", "qty": 2}]
    rewards     = Column(JSON, nullable=False, default=list)
    xp_reward   = Column(Integer, nullable=False, default=100)
    is_active   = Column(Boolean, nullable=False, default=True)


class PlayerDailyQuest(Base):
    """Player's progress on one quest for a given cycle."""
    __tablename__ = "player_daily_quests"

    id          = Column(Integer, primary_key=True)
    user_id     = Column(Integer, ForeignKey("users.id"), nullable=False)
    template_id = Column(Integer, ForeignKey("daily_quest_templates.id"), nullable=False)
    cycle_key   = Column(String(32), nullable=False)  # "daily_2026-03-24"

    progress    = Column(Integer, nullable=False, default=0)
    target      = Column(Integer, nullable=False, default=1)
    completed   = Column(Boolean, nullable=False, default=False)
    claimed     = Column(Boolean, nullable=False, default=False)
    completed_at = Column(DateTime, nullable=True)
    claimed_at  = Column(DateTime, nullable=True)

    template    = relationship("DailyQuestTemplate")

    __table_args__ = (
        UniqueConstraint("user_id", "template_id", "cycle_key", name="uq_player_quest_cycle"),
    )


class PlayerStreak(Base):
    """Tracks daily login streak and quest-completion streak."""
    __tablename__ = "player_streaks"

    id                     = Column(Integer, primary_key=True)
    user_id                = Column(Integer, ForeignKey("users.id"), unique=True, nullable=False)

    login_streak           = Column(Integer, nullable=False, default=0)
    last_login_date        = Column(String(12), nullable=True)
    max_login_streak       = Column(Integer, nullable=False, default=0)

    quest_streak           = Column(Integer, nullable=False, default=0)
    last_quest_date        = Column(String(12), nullable=True)
    max_quest_streak       = Column(Integer, nullable=False, default=0)

    total_quests_completed = Column(Integer, nullable=False, default=0)
    updated_at             = Column(DateTime, nullable=False, default=datetime.utcnow)


# ══════════════════════════════════════════════════════════════════════════════
# 2. BATTLE BETTING MARKET (parimutuel)
# ══════════════════════════════════════════════════════════════════════════════

class BetStatus(str, enum.Enum):
    open      = "open"
    locked    = "locked"
    settled   = "settled"
    cancelled = "cancelled"


class BettingMarket(Base):
    """One parimutuel betting market per PvP match or live battle."""
    __tablename__ = "betting_markets"

    id             = Column(Integer, primary_key=True)
    match_type     = Column(String(32), nullable=False)  # "pvp" | "live_battle"
    match_id       = Column(String(64), nullable=False)
    status         = Column(Enum(BetStatus), nullable=False, default=BetStatus.open)
    winner_ref     = Column(String(64), nullable=True)

    opens_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
    locks_at       = Column(DateTime, nullable=True)
    settled_at     = Column(DateTime, nullable=True)

    # House edge loaded from config; stored here for historical accuracy
    house_edge_pct = Column(Float, nullable=False, default=0.05)

    total_pool     = Column(Numeric(14, 2), nullable=False, default=0)
    side_a_pool    = Column(Numeric(14, 2), nullable=False, default=0)
    side_b_pool    = Column(Numeric(14, 2), nullable=False, default=0)

    bets           = relationship("MatchBet", back_populates="market",
                                  cascade="all, delete-orphan")

    __table_args__ = (
        UniqueConstraint("match_type", "match_id", name="uq_market_match"),
    )


class MatchBet(Base):
    """One player's bet on a specific fight side (gold)."""
    __tablename__ = "match_bets"

    id         = Column(Integer, primary_key=True)
    market_id  = Column(Integer, ForeignKey("betting_markets.id"), nullable=False)
    bettor_id  = Column(Integer, ForeignKey("users.id"), nullable=False)

    side       = Column(String(4), nullable=False)      # "A" | "B"
    amount     = Column(Numeric(12, 2), nullable=False) # gold

    payout     = Column(Numeric(12, 2), nullable=True)
    is_winner  = Column(Boolean, nullable=True)
    settled_at = Column(DateTime, nullable=True)
    placed_at  = Column(DateTime, nullable=False, default=datetime.utcnow)

    market     = relationship("BettingMarket", back_populates="bets")

    __table_args__ = (
        UniqueConstraint("market_id", "bettor_id", name="uq_bet_per_market"),
        CheckConstraint("amount > 0", name="ck_bet_amount_positive"),
    )


# ══════════════════════════════════════════════════════════════════════════════
# 3. HERO HEALING SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

class HealStatus(str, enum.Enum):
    queued      = "queued"
    in_progress = "in_progress"
    completed   = "completed"
    cancelled   = "cancelled"


class HeroHealOrder(Base):
    """
    Heal order for one body part of a hero.
    Heals over real time; gold speeds it up.
    Costs/durations configured in game_config.yaml (healing section).
    """
    __tablename__ = "hero_heal_orders"

    id               = Column(Integer, primary_key=True)
    hero_id          = Column(Integer, ForeignKey("heroes.id"), nullable=False)
    user_id          = Column(Integer, ForeignKey("users.id"), nullable=False)

    part_name        = Column(String(32), nullable=False)  # "head" | "torso" | …
    severity         = Column(String(32), nullable=False)  # "injured" | "severely_injured"

    heal_duration_sec = Column(Integer, nullable=False)
    started_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
    completes_at     = Column(DateTime, nullable=False)

    gold_spent       = Column(Numeric(10, 2), nullable=False, default=0)  # total gold paid

    status           = Column(Enum(HealStatus), nullable=False, default=HealStatus.in_progress)
    completed_at     = Column(DateTime, nullable=True)

    __table_args__ = (
        UniqueConstraint("hero_id", "part_name", name="uq_heal_order_part"),
    )


# ══════════════════════════════════════════════════════════════════════════════
# 4. RESURRECTION SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

class ResurrectionAttempt(Base):
    """
    Record of each resurrection artifact craft attempt.
    5% craft success chance (configured in game_config.yaml).
    Materials consumed even on failure.
    """
    __tablename__ = "resurrection_attempts"

    id                 = Column(Integer, primary_key=True)
    hero_id            = Column(Integer, ForeignKey("heroes.id"), nullable=False)
    user_id            = Column(Integer, ForeignKey("users.id"), nullable=False)

    craft_attempted_at = Column(DateTime, nullable=False, default=datetime.utcnow)
    craft_roll         = Column(Float, nullable=False)
    craft_succeeded    = Column(Boolean, nullable=False)
    craft_materials    = Column(JSON, nullable=False, default=list)
    gold_paid          = Column(Integer, nullable=False, default=0)

    used_at            = Column(DateTime, nullable=True)
    resurrection_ok    = Column(Boolean, nullable=True)
    notes              = Column(Text, nullable=True)


# ══════════════════════════════════════════════════════════════════════════════
# 5. CURRENCY SHOP (Stripe → in-game gold)
# ══════════════════════════════════════════════════════════════════════════════

class PurchaseStatus(str, enum.Enum):
    pending   = "pending"
    completed = "completed"
    failed    = "failed"
    refunded  = "refunded"


class CurrencyPurchase(Base):
    """
    Record of a real-money purchase of in-game gold via Stripe.
    Available packages are defined in config/game_config.yaml → currency_shop.packages
    """
    __tablename__ = "currency_purchases"

    id                    = Column(Integer, primary_key=True)
    user_id               = Column(Integer, ForeignKey("users.id"), nullable=False)

    package_id            = Column(String(32), nullable=False)   # e.g. "starter", "mega"
    stripe_payment_intent = Column(String(128), nullable=True)
    stripe_charge_id      = Column(String(128), nullable=True)

    amount_usd            = Column(Numeric(8, 2), nullable=False)
    gold_granted          = Column(Integer, nullable=False)
    bonus_gold            = Column(Integer, nullable=False, default=0)

    status                = Column(Enum(PurchaseStatus), nullable=False,
                                   default=PurchaseStatus.pending)
    created_at            = Column(DateTime, nullable=False, default=datetime.utcnow)
    completed_at          = Column(DateTime, nullable=True)

    __table_args__ = (
        UniqueConstraint("stripe_payment_intent", name="uq_currency_stripe_intent"),
    )


# ══════════════════════════════════════════════════════════════════════════════
# 6. ALLIANCE SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

class AllianceRole(str, enum.Enum):
    founder = "founder"
    leader  = "leader"
    officer = "officer"
    member  = "member"


class AllianceStatus(str, enum.Enum):
    active    = "active"
    disbanded = "disbanded"


class Alliance(Base):
    """
    A permanent political union of up to 5 clans.
    Size limits and penalties configured in game_config.yaml → alliance.
    """
    __tablename__ = "alliances"

    id               = Column(Integer, primary_key=True)
    name             = Column(String(128), unique=True, nullable=False)
    tag              = Column(String(8),   unique=True, nullable=False)
    description      = Column(Text, nullable=True)
    status           = Column(Enum(AllianceStatus), nullable=False, default=AllianceStatus.active)

    founder_clan_id  = Column(Integer, ForeignKey("clans.id"), nullable=False)
    leader_clan_id   = Column(Integer, ForeignKey("clans.id"), nullable=False)

    max_clans        = Column(Integer, nullable=False, default=5)
    max_members      = Column(Integer, nullable=False, default=150)
    weekly_upkeep    = Column(Integer, nullable=False, default=1000)  # gold
    size_penalty_pct = Column(Float,   nullable=False, default=0.0)

    xp               = Column(Integer, nullable=False, default=0)
    rank             = Column(Integer, nullable=False, default=0)  # 0=guild, 1=order, 2=empire

    created_at       = Column(DateTime, nullable=False, default=datetime.utcnow)
    disbanded_at     = Column(DateTime, nullable=True)

    members          = relationship("AllianceMember",   back_populates="alliance",
                                    cascade="all, delete-orphan")
    war_chest        = relationship("AllianceWarChest", back_populates="alliance",
                                    uselist=False, cascade="all, delete-orphan")


class AllianceMember(Base):
    """Clan membership in an alliance."""
    __tablename__ = "alliance_members"

    id           = Column(Integer, primary_key=True)
    alliance_id  = Column(Integer, ForeignKey("alliances.id"), nullable=False)
    clan_id      = Column(Integer, ForeignKey("clans.id"), nullable=False)
    role         = Column(Enum(AllianceRole), nullable=False, default=AllianceRole.member)
    joined_at    = Column(DateTime, nullable=False, default=datetime.utcnow)
    contribution = Column(Integer, nullable=False, default=0)

    alliance     = relationship("Alliance", back_populates="members")

    __table_args__ = (
        UniqueConstraint("alliance_id", "clan_id", name="uq_alliance_clan"),
    )


class AllianceWarChest(Base):
    """Shared gold + resource treasury of an alliance."""
    __tablename__ = "alliance_war_chests"

    id             = Column(Integer, primary_key=True)
    alliance_id    = Column(Integer, ForeignKey("alliances.id"), unique=True, nullable=False)

    currency       = Column(Integer, nullable=False, default=0)   # gold
    resources      = Column(JSON, nullable=False, default=dict)

    pending_income = Column(Integer, nullable=False, default=0)
    last_upkeep_at = Column(DateTime, nullable=True)
    updated_at     = Column(DateTime, nullable=False, default=datetime.utcnow)

    alliance       = relationship("Alliance", back_populates="war_chest")
