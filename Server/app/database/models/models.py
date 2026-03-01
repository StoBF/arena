from sqlalchemy import (
    Column, Integer, String, Float, ForeignKey, DateTime, Text, UniqueConstraint, Boolean, JSON, Enum, Numeric, CheckConstraint
)
from sqlalchemy.orm import relationship
from datetime import datetime, timedelta
from app.database.base import Base
import enum
from app.database.models.user import User
from app.core.enums import AuctionStatus
from sqlalchemy.orm import Session
from uuid import uuid4
from decimal import Decimal

# Hero class is now only in hero.py

class ItemType(enum.Enum):
    equipment = "equipment"
    artifact = "artifact"
    resource = "resource"
    material = "material"
    consumable = "consumable"
    weapon = "weapon"
    armor = "armor"
    helmet = "helmet"

class SlotType(enum.Enum):
    weapon = "weapon"
    helmet = "helmet"
    spacesuit = "spacesuit"
    boots = "boots"
    artifact = "artifact"
    shield = "shield"
    gadget = "gadget"
    implant = "implant"
    utility_belt = "utility_belt"

class Item(Base):
    __tablename__ = "items"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    description = Column(Text, nullable=True)
    type = Column(Enum(ItemType), nullable=False, default=ItemType.equipment)
    bonus_strength = Column(Integer, default=0)
    bonus_agility = Column(Integer, default=0)
    bonus_intelligence = Column(Integer, default=0)
    bonus_endurance = Column(Integer, default=0)
    bonus_speed = Column(Integer, default=0)
    bonus_health = Column(Integer, default=0)
    bonus_defense = Column(Integer, default=0)
    bonus_luck = Column(Integer, default=0)
    slot_type = Column(String, nullable=False, default="weapon")

    stash_items = relationship("Stash", back_populates="item")
    auctions = relationship("Auction", back_populates="item")
    equipped_in = relationship("Equipment", back_populates="item")

class Stash(Base):
    __tablename__ = "stash"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    item_id = Column(Integer, ForeignKey("items.id"), nullable=False)
    quantity = Column(Integer, default=1)
    __table_args__ = (UniqueConstraint('user_id', 'item_id', name='_user_item_uc'),)

    owner = relationship("User", back_populates="items")
    item = relationship("Item", back_populates="stash_items")

class Auction(Base):
    __tablename__ = "auctions"

    id = Column(Integer, primary_key=True, index=True)
    item_id = Column(Integer, ForeignKey("items.id"), nullable=False)
    seller_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)  # user
    start_price = Column(Numeric(12, 2), nullable=False)
    current_price = Column(Numeric(12, 2), nullable=False)
    end_time = Column(DateTime, nullable=False, index=True)
    winner_id = Column(Integer, ForeignKey("users.id"))  # user
    quantity = Column(Integer, default=1)  # кількість предметів у лоті
    status = Column(Enum(AuctionStatus), default=AuctionStatus.ACTIVE, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    __table_args__ = (
        CheckConstraint('start_price > 0', name='ck_auction_start_price_positive'),
        CheckConstraint('current_price > 0', name='ck_auction_current_price_positive'),
    )

    seller = relationship("User", foreign_keys=[seller_id], backref="auctions")
    item = relationship("Item", back_populates="auctions")
    bids = relationship("Bid", back_populates="auction")
    winner = relationship("User", foreign_keys=[winner_id])

class Bid(Base):
    __tablename__ = "bids"

    id = Column(Integer, primary_key=True, index=True)
    request_id = Column(String, nullable=True, unique=True, index=True)  # Idempotency key (UUID)
    auction_id = Column(Integer, ForeignKey("auctions.id"), nullable=True, index=True)
    lot_id = Column(Integer, ForeignKey("auction_lots.id"), nullable=True, index=True)
    bidder_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)  # user
    amount = Column(Numeric(12, 2), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    __table_args__ = (
        CheckConstraint('amount > 0', name='ck_bid_amount_positive'),
    )

    auction = relationship("Auction", back_populates="bids")
    auction_lot = relationship("AuctionLot", back_populates="bids")
    bidder = relationship("User")

class Announcement(Base):
    __tablename__ = "announcements"

    id = Column(Integer, primary_key=True, index=True)
    message = Column(Text, nullable=False)
    author_id = Column(Integer, ForeignKey("users.id"))
    created_at = Column(DateTime, default=datetime.utcnow)

    author = relationship("User")

class Equipment(Base):
    __tablename__ = "equipment"
    id = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("heroes.id"), nullable=False)
    item_id = Column(Integer, ForeignKey("items.id"), nullable=False)
    slot   = Column(String, nullable=False)
    __table_args__ = (UniqueConstraint('hero_id', 'slot', name='_hero_slot_uc'),)

    hero = relationship("app.database.models.hero.Hero", back_populates="equipment_items")
    item = relationship("Item", back_populates="equipped_in")

class AuctionLot(Base):
    __tablename__ = "auction_lots"

    id = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("heroes.id"), nullable=False, unique=True)
    seller_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    starting_price = Column(Numeric(12, 2), nullable=False)
    current_price = Column(Numeric(12, 2), nullable=False)
    buyout_price = Column(Numeric(12, 2), nullable=True)
    end_time = Column(DateTime, nullable=False, index=True)
    winner_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    status = Column(Enum(AuctionStatus), default=AuctionStatus.ACTIVE, index=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    __table_args__ = (
        CheckConstraint('starting_price > 0', name='ck_lot_starting_price_positive'),
        CheckConstraint('current_price > 0', name='ck_lot_current_price_positive'),
        CheckConstraint('buyout_price IS NULL OR buyout_price > 0', name='ck_lot_buyout_price_positive'),
    )

    hero = relationship("app.database.models.hero.Hero")
    seller = relationship("User", foreign_keys=[seller_id])
    winner = relationship("User", foreign_keys=[winner_id])
    bids = relationship("Bid", back_populates="auction_lot")

class AutoBid(Base):
    __tablename__ = "auto_bids"

    id = Column(Integer, primary_key=True, index=True)
    auction_id = Column(Integer, ForeignKey("auctions.id"), nullable=True)
    lot_id = Column(Integer, ForeignKey("auction_lots.id"), nullable=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    max_amount = Column(Numeric(12, 2), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    __table_args__ = (
        CheckConstraint('max_amount > 0', name='ck_autobid_max_amount_positive'),
    )

    auction = relationship("Auction")
    lot = relationship("AuctionLot")
    user = relationship("User")

class ChatMessage(Base):
    __tablename__ = "chat_messages"
    id = Column(Integer, primary_key=True, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    recipient_id = Column(Integer, ForeignKey("users.id"), nullable=True)  # None для публічних каналів
    text = Column(String, nullable=False)
    channel = Column(String(20), nullable=False, default="general")  # general, trade, private
    created_at = Column(DateTime, default=datetime.utcnow)
    sender = relationship("User", foreign_keys=[sender_id])
    recipient = relationship("User", foreign_keys=[recipient_id])

class OfflineMessage(Base):
    __tablename__ = "offline_messages"
    id = Column(Integer, primary_key=True, index=True)
    sender_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    recipient_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    text = Column(String, nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow)
    delivered = Column(Boolean, default=False)
    sender = relationship("User", foreign_keys=[sender_id])
    recipient = relationship("User", foreign_keys=[recipient_id])

class PvPMatch(Base):
    __tablename__ = "pvp_matches"
    id = Column(Integer, primary_key=True)
    player1_id = Column(Integer, ForeignKey("users.id"))
    player2_id = Column(Integer, ForeignKey("users.id"))
    winner_id = Column(Integer, ForeignKey("users.id"), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    finished_at = Column(DateTime, nullable=True)
    logs = relationship("PvPBattleLog", back_populates="match")

class PvPBattleLog(Base):
    __tablename__ = "pvp_battle_logs"
    id = Column(Integer, primary_key=True)
    match_id = Column(Integer, ForeignKey("pvp_matches.id"))
    events = Column(JSON)
    outcome = Column(String)  # e.g. "player1_win", "draw"
    match = relationship("PvPMatch", back_populates="logs")

class LeaderboardEntry(Base):
    __tablename__ = "leaderboard"
    user_id = Column(Integer, ForeignKey("users.id"), primary_key=True)
    rating = Column(Numeric(8, 2), default=Decimal('1000.00'))
    wins = Column(Integer, default=0)
    losses = Column(Integer, default=0)
