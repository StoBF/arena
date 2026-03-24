"""
Clan system models — full foundation.

Entities:
  Clan                     – core entity
  ClanMember               – member + role + trust + permissions
  ClanApplication          – join requests
  ClanActivityLog          – audit trail
  ClanStorageItem          – shared resource inventory
  ClanStorageTransaction   – audit for every storage move
  ClanMeetup               – offline / online events with QR
  ClanMeetupParticipant    – check-in records
  RaidTicket               – entry token for raid bosses
  RaidRegistration         – clan/party request for a boss slot
  RaidTournament           – elimination tournament for boss access
  RaidTournamentMatch      – single match inside a tournament
"""
from __future__ import annotations

import enum
from datetime import datetime

from sqlalchemy import (
    Boolean, CheckConstraint, Column, DateTime, Enum as SAEnum,
    ForeignKey, Integer, JSON, Numeric, String, Text, UniqueConstraint
)
from sqlalchemy.orm import relationship

from app.database.base import Base


# ── Enums ─────────────────────────────────────────────────────────────────────

class ClanType(str, enum.Enum):
    local         = "local"
    regional      = "regional"
    international = "international"

class ClanMode(str, enum.Enum):
    casual      = "casual"
    competitive = "competitive"
    pve         = "pve"
    pvp         = "pvp"
    mixed       = "mixed"

class RecruitmentMode(str, enum.Enum):
    open          = "open"
    by_application = "by_application"
    invite_only   = "invite_only"

class ClanRole(str, enum.Enum):
    leader       = "leader"
    co_leader    = "co_leader"
    officer      = "officer"
    quartermaster = "quartermaster"
    crafter      = "crafter"
    recruiter    = "recruiter"
    raid_captain = "raid_captain"
    member       = "member"
    trial        = "trial"

class ApplicationStatus(str, enum.Enum):
    new         = "new"
    in_review   = "in_review"
    interview   = "interview"
    trial       = "trial"
    accepted    = "accepted"
    rejected    = "rejected"

class MeetupStatus(str, enum.Enum):
    scheduled = "scheduled"
    active    = "active"
    closed    = "closed"
    cancelled = "cancelled"

class StorageAction(str, enum.Enum):
    deposit  = "deposit"
    withdraw = "withdraw"
    reserve  = "reserve"
    release  = "release"
    craft    = "craft"
    transfer = "transfer"

class TicketOwnerType(str, enum.Enum):
    user = "user"
    clan = "clan"

class TournamentStatus(str, enum.Enum):
    pending   = "pending"
    active    = "active"
    completed = "completed"
    cancelled = "cancelled"

class MatchStatus(str, enum.Enum):
    pending   = "pending"
    active    = "active"
    completed = "completed"


# ── Clan ──────────────────────────────────────────────────────────────────────

class Clan(Base):
    __tablename__ = "clans"

    id                  = Column(Integer, primary_key=True, index=True)
    name                = Column(String(64),  nullable=False, unique=True)
    slug                = Column(String(80),  nullable=False, unique=True, index=True)
    description         = Column(Text,        default="")
    emblem_path         = Column(String(256), nullable=True)   # stored file path

    # Territory
    country_code        = Column(String(4),   nullable=False, default="")
    region_name         = Column(String(128), default="")
    city_name           = Column(String(128), default="")
    district_name       = Column(String(128), default="")
    language            = Column(String(8),   default="en")

    # Meta
    clan_type           = Column(SAEnum(ClanType,        name="clan_type"),
                                  nullable=False, default=ClanType.local)
    clan_mode           = Column(SAEnum(ClanMode,        name="clan_mode"),
                                  nullable=False, default=ClanMode.mixed)
    offline_friendly    = Column(Boolean, default=False)
    recruitment_mode    = Column(SAEnum(RecruitmentMode, name="recruitment_mode"),
                                  nullable=False, default=RecruitmentMode.by_application)

    # Progression
    level               = Column(Integer, nullable=False, default=1)
    experience          = Column(Integer, nullable=False, default=0)
    reputation          = Column(Integer, nullable=False, default=0)
    treasury_currency   = Column(Numeric(14, 2), nullable=False, default=0)
    member_limit        = Column(Integer, nullable=False, default=30)

    owner_id            = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"),
                                  nullable=True, index=True)
    created_at          = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at          = Column(DateTime, default=datetime.utcnow,
                                  onupdate=datetime.utcnow, nullable=False)
    disbanded_at        = Column(DateTime, nullable=True)

    # Relationships
    members             = relationship("ClanMember",      back_populates="clan",
                                        cascade="all, delete-orphan")
    applications        = relationship("ClanApplication", back_populates="clan",
                                        cascade="all, delete-orphan")
    activity_log        = relationship("ClanActivityLog", back_populates="clan",
                                        cascade="all, delete-orphan")
    storage_items       = relationship("ClanStorageItem", back_populates="clan",
                                        cascade="all, delete-orphan")
    meetups             = relationship("ClanMeetup",      back_populates="clan",
                                        cascade="all, delete-orphan")


# ── ClanMember ────────────────────────────────────────────────────────────────

class ClanMember(Base):
    __tablename__ = "clan_members"

    id                   = Column(Integer, primary_key=True, index=True)
    clan_id              = Column(Integer, ForeignKey("clans.id", ondelete="CASCADE"),
                                   nullable=False, index=True)
    user_id              = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"),
                                   nullable=False, index=True)
    role                 = Column(SAEnum(ClanRole, name="clan_role"),
                                   nullable=False, default=ClanRole.member)
    nickname             = Column(String(64), nullable=True)   # call-sign

    # Trust
    trust_level          = Column(Integer, nullable=False, default=0)
    trust_points         = Column(Integer, nullable=False, default=0)
    contribution_score   = Column(Integer, nullable=False, default=0)

    # Granular permissions (override role defaults)
    can_manage_members   = Column(Boolean, default=False)
    can_manage_storage   = Column(Boolean, default=False)
    can_withdraw_storage = Column(Boolean, default=False)
    can_craft_storage    = Column(Boolean, default=False)
    can_manage_chat      = Column(Boolean, default=False)
    can_manage_events    = Column(Boolean, default=False)
    can_manage_recruitment = Column(Boolean, default=False)

    joined_at            = Column(DateTime, default=datetime.utcnow, nullable=False)
    last_active_at       = Column(DateTime, default=datetime.utcnow, nullable=False)

    clan = relationship("Clan", back_populates="members")

    __table_args__ = (
        UniqueConstraint("clan_id", "user_id", name="uq_clan_member"),
    )


# ── ClanApplication ───────────────────────────────────────────────────────────

class ClanApplication(Base):
    __tablename__ = "clan_applications"

    id               = Column(Integer, primary_key=True, index=True)
    clan_id          = Column(Integer, ForeignKey("clans.id", ondelete="CASCADE"),
                               nullable=False, index=True)
    user_id          = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"),
                               nullable=False, index=True)
    message          = Column(Text, default="")
    city_name        = Column(String(128), default="")
    playstyle        = Column(String(64),  default="")
    availability_text = Column(String(256), default="")
    status           = Column(SAEnum(ApplicationStatus, name="application_status"),
                               nullable=False, default=ApplicationStatus.new)
    reviewed_by      = Column(Integer, ForeignKey("users.id"), nullable=True)
    reviewed_at      = Column(DateTime, nullable=True)
    decision_note    = Column(Text, default="")
    created_at       = Column(DateTime, default=datetime.utcnow, nullable=False)

    clan = relationship("Clan", back_populates="applications")

    __table_args__ = (
        # One pending application per (clan, user) at a time
        UniqueConstraint("clan_id", "user_id", name="uq_clan_application"),
    )


# ── ClanActivityLog ───────────────────────────────────────────────────────────

class ClanActivityLog(Base):
    __tablename__ = "clan_activity_log"

    id            = Column(Integer, primary_key=True, index=True)
    clan_id       = Column(Integer, ForeignKey("clans.id", ondelete="CASCADE"),
                            nullable=False, index=True)
    actor_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"),
                            nullable=True)
    action_type   = Column(String(64),  nullable=False)
    payload_json  = Column(JSON, nullable=False, default=dict)
    created_at    = Column(DateTime, default=datetime.utcnow, nullable=False)

    clan = relationship("Clan", back_populates="activity_log")


# ── ClanStorageItem ───────────────────────────────────────────────────────────

class ClanStorageItem(Base):
    """Shared clan resource stash. item_type='resource'|'armor'|'recipe'|'ticket'"""
    __tablename__ = "clan_storage_items"

    id                = Column(Integer, primary_key=True, index=True)
    clan_id           = Column(Integer, ForeignKey("clans.id", ondelete="CASCADE"),
                                nullable=False, index=True)
    item_type         = Column(String(32), nullable=False)
    item_id           = Column(Integer, nullable=False)      # FK resolved at runtime
    quantity          = Column(Integer, nullable=False, default=0)
    reserved_quantity = Column(Integer, nullable=False, default=0)
    created_at        = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at        = Column(DateTime, default=datetime.utcnow,
                                onupdate=datetime.utcnow, nullable=False)

    clan = relationship("Clan", back_populates="storage_items")

    __table_args__ = (
        UniqueConstraint("clan_id", "item_type", "item_id",
                          name="uq_clan_storage_item"),
        CheckConstraint("quantity >= 0",          name="ck_storage_qty_positive"),
        CheckConstraint("reserved_quantity >= 0", name="ck_storage_reserve_positive"),
    )


class ClanStorageTransaction(Base):
    __tablename__ = "clan_storage_transactions"

    id            = Column(Integer, primary_key=True, index=True)
    clan_id       = Column(Integer, ForeignKey("clans.id", ondelete="CASCADE"),
                            nullable=False, index=True)
    actor_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"),
                            nullable=True)
    action_type   = Column(SAEnum(StorageAction, name="storage_action"),
                            nullable=False)
    item_type     = Column(String(32), nullable=False)
    item_id       = Column(Integer, nullable=False)
    quantity      = Column(Integer, nullable=False)
    note          = Column(String(256), default="")
    created_at    = Column(DateTime, default=datetime.utcnow, nullable=False)


# ── ClanMeetup + QR ───────────────────────────────────────────────────────────

class ClanMeetup(Base):
    __tablename__ = "clan_meetups"

    id            = Column(Integer, primary_key=True, index=True)
    clan_id       = Column(Integer, ForeignKey("clans.id", ondelete="CASCADE"),
                            nullable=False, index=True)
    title         = Column(String(128), nullable=False)
    description   = Column(Text, default="")
    city_name     = Column(String(128), default="")
    scheduled_at  = Column(DateTime, nullable=True)
    created_by    = Column(Integer, ForeignKey("users.id"), nullable=False)
    status        = Column(SAEnum(MeetupStatus, name="meetup_status"),
                            nullable=False, default=MeetupStatus.scheduled)
    qr_secret     = Column(String(64),  nullable=True)
    qr_expires_at = Column(DateTime,    nullable=True)
    created_at    = Column(DateTime, default=datetime.utcnow, nullable=False)

    clan         = relationship("Clan", back_populates="meetups")
    participants = relationship("ClanMeetupParticipant", back_populates="meetup",
                                 cascade="all, delete-orphan")


class ClanMeetupParticipant(Base):
    __tablename__ = "clan_meetup_participants"

    id                  = Column(Integer, primary_key=True, index=True)
    meetup_id           = Column(Integer, ForeignKey("clan_meetups.id",
                                                      ondelete="CASCADE"),
                                  nullable=False, index=True)
    user_id             = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"),
                                  nullable=False)
    verified_at         = Column(DateTime, default=datetime.utcnow, nullable=False)
    verification_method = Column(String(32), default="qr")

    meetup = relationship("ClanMeetup", back_populates="participants")

    __table_args__ = (
        UniqueConstraint("meetup_id", "user_id", name="uq_meetup_participant"),
    )


# ── RaidTicket ────────────────────────────────────────────────────────────────

class RaidTicket(Base):
    __tablename__ = "raid_tickets"

    id             = Column(Integer, primary_key=True, index=True)
    owner_type     = Column(SAEnum(TicketOwnerType, name="ticket_owner_type"),
                             nullable=False, default=TicketOwnerType.user)
    owner_user_id  = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"),
                             nullable=True, index=True)
    owner_clan_id  = Column(Integer, ForeignKey("clans.id", ondelete="CASCADE"),
                             nullable=True, index=True)
    ticket_type    = Column(String(32), nullable=False, default="standard")
    boss_tier      = Column(Integer, nullable=False, default=1)
    tradable       = Column(Boolean, default=True)
    created_at     = Column(DateTime, default=datetime.utcnow, nullable=False)
    expires_at     = Column(DateTime, nullable=True)

    __table_args__ = (
        CheckConstraint(
            "(owner_user_id IS NOT NULL) OR (owner_clan_id IS NOT NULL)",
            name="ck_ticket_has_owner"
        ),
    )


# ── RaidRegistration, RaidTournament, RaidTournamentMatch ─────────────────────

class ClanChatMessage(Base):
    __tablename__ = "clan_chat_messages"

    id             = Column(Integer, primary_key=True, index=True)
    clan_id        = Column(Integer, ForeignKey("clans.id", ondelete="CASCADE"),
                             nullable=False, index=True)
    sender_user_id = Column(Integer, ForeignKey("users.id", ondelete="SET NULL"),
                             nullable=True)
    message_type   = Column(String(16), nullable=False, default="chat")
    content        = Column(Text, nullable=False)
    created_at     = Column(DateTime, default=datetime.utcnow, nullable=False,
                             index=True)


class RaidRegistration(Base):
    __tablename__ = "raid_registrations"

    id                  = Column(Integer, primary_key=True, index=True)
    boss_event_id       = Column(Integer, nullable=False, index=True)
    registration_type   = Column(String(16), nullable=False)  # clan | party | solo
    clan_id             = Column(Integer, ForeignKey("clans.id"), nullable=True)
    party_leader_id     = Column(Integer, ForeignKey("users.id"), nullable=True)
    created_by          = Column(Integer, ForeignKey("users.id"), nullable=False)
    ticket_commitment   = Column(Integer, default=0)
    status              = Column(String(32), nullable=False, default="pending")
    created_at          = Column(DateTime, default=datetime.utcnow, nullable=False)


class RaidTournament(Base):
    __tablename__ = "raid_tournaments"

    id              = Column(Integer, primary_key=True, index=True)
    boss_event_id   = Column(Integer, nullable=False, index=True)
    status          = Column(SAEnum(TournamentStatus, name="tournament_status"),
                              nullable=False, default=TournamentStatus.pending)
    winner_clan_id  = Column(Integer, ForeignKey("clans.id"), nullable=True)
    winner_party_id = Column(Integer, nullable=True)
    created_at      = Column(DateTime, default=datetime.utcnow, nullable=False)

    matches = relationship("RaidTournamentMatch", back_populates="tournament",
                            cascade="all, delete-orphan")


class RaidTournamentMatch(Base):
    __tablename__ = "raid_tournament_matches"

    id            = Column(Integer, primary_key=True, index=True)
    tournament_id = Column(Integer, ForeignKey("raid_tournaments.id",
                                                ondelete="CASCADE"),
                            nullable=False, index=True)
    side_a_type   = Column(String(16), nullable=False)   # clan | party
    side_a_id     = Column(Integer, nullable=False)
    side_b_type   = Column(String(16), nullable=True)
    side_b_id     = Column(Integer, nullable=True)
    winner_type   = Column(String(16), nullable=True)
    winner_id     = Column(Integer, nullable=True)
    status        = Column(SAEnum(MatchStatus, name="match_status"),
                            nullable=False, default=MatchStatus.pending)
    created_at    = Column(DateTime, default=datetime.utcnow, nullable=False)

    tournament = relationship("RaidTournament", back_populates="matches")
