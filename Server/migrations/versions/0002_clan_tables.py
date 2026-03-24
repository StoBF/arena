"""Clan system tables

Creates all 12 clan-related tables:
  clans, clan_members, clan_applications,
  clan_activity_log, clan_storage_items, clan_storage_transactions,
  clan_meetups, clan_meetup_participants, clan_chat_messages,
  raid_tickets, raid_registrations,
  raid_tournaments, raid_tournament_matches

Revision ID: 0002
Revises:     0001
Create Date: 2026-03-24
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: Union[str, None] = "0001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    bind = op.get_bind()

    # ── ENUM types (PostgreSQL) ────────────────────────────────────────────
    # Safe to call multiple times — the helper checks existence.
    def _create_enum(name: str, *values: str) -> None:
        exists = bind.execute(
            sa.text(
                "SELECT 1 FROM pg_type WHERE typname = :n"
            ),
            {"n": name},
        ).fetchone()
        if not exists:
            types = ", ".join(f"'{v}'" for v in values)
            bind.execute(sa.text(f"CREATE TYPE {name} AS ENUM ({types})"))

    # Guard: PostgreSQL only
    if bind.dialect.name == "postgresql":
        _create_enum("clan_type",          "local", "regional", "international")
        _create_enum("clan_mode",          "casual", "competitive", "pve", "pvp", "mixed")
        _create_enum("recruitment_mode",   "open", "by_application", "invite_only")
        _create_enum("clan_role",          "leader", "co_leader", "officer",
                                           "quartermaster", "crafter", "recruiter",
                                           "raid_captain", "member", "trial")
        _create_enum("application_status", "new", "in_review", "interview",
                                           "trial", "accepted", "rejected")
        _create_enum("meetup_status",      "scheduled", "active", "closed", "cancelled")
        _create_enum("storage_action",     "deposit", "withdraw", "reserve",
                                           "release", "craft", "transfer")
        _create_enum("ticket_owner_type",  "user", "clan")
        _create_enum("tournament_status",  "pending", "active", "completed", "cancelled")
        _create_enum("match_status",       "pending", "active", "completed")

    # ── clans ──────────────────────────────────────────────────────────────
    if not _table_exists(bind, "clans"):
        op.create_table(
            "clans",
            sa.Column("id",                sa.Integer(),    primary_key=True),
            sa.Column("name",              sa.String(64),   nullable=False, unique=True),
            sa.Column("slug",              sa.String(80),   nullable=False, unique=True),
            sa.Column("description",       sa.Text(),       nullable=True),
            sa.Column("emblem_path",       sa.String(256),  nullable=True),
            sa.Column("country_code",      sa.String(4),    nullable=False, server_default=""),
            sa.Column("region_name",       sa.String(128),  nullable=True),
            sa.Column("city_name",         sa.String(128),  nullable=True),
            sa.Column("district_name",     sa.String(128),  nullable=True),
            sa.Column("language",          sa.String(8),    server_default="en"),
            sa.Column("clan_type",         sa.String(32),   nullable=False, server_default="local"),
            sa.Column("clan_mode",         sa.String(32),   nullable=False, server_default="mixed"),
            sa.Column("offline_friendly",  sa.Boolean(),    server_default="false"),
            sa.Column("recruitment_mode",  sa.String(32),   nullable=False, server_default="by_application"),
            sa.Column("level",             sa.Integer(),    nullable=False, server_default="1"),
            sa.Column("experience",        sa.Integer(),    nullable=False, server_default="0"),
            sa.Column("reputation",        sa.Integer(),    nullable=False, server_default="0"),
            sa.Column("treasury_currency", sa.Numeric(14,2),server_default="0"),
            sa.Column("member_limit",      sa.Integer(),    nullable=False, server_default="30"),
            sa.Column("owner_id",          sa.Integer(),    sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("created_at",        sa.DateTime(),   nullable=False),
            sa.Column("updated_at",        sa.DateTime(),   nullable=False),
            sa.Column("disbanded_at",      sa.DateTime(),   nullable=True),
        )
        op.create_index("ix_clans_slug",     "clans", ["slug"])
        op.create_index("ix_clans_owner_id", "clans", ["owner_id"])

    # ── clan_members ───────────────────────────────────────────────────────
    if not _table_exists(bind, "clan_members"):
        op.create_table(
            "clan_members",
            sa.Column("id",                      sa.Integer(), primary_key=True),
            sa.Column("clan_id",                 sa.Integer(), sa.ForeignKey("clans.id", ondelete="CASCADE"), nullable=False),
            sa.Column("user_id",                 sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("role",                    sa.String(32), nullable=False, server_default="member"),
            sa.Column("nickname",                sa.String(64), nullable=True),
            sa.Column("trust_level",             sa.Integer(), nullable=False, server_default="0"),
            sa.Column("trust_points",            sa.Integer(), nullable=False, server_default="0"),
            sa.Column("contribution_score",      sa.Integer(), nullable=False, server_default="0"),
            sa.Column("can_manage_members",      sa.Boolean(), server_default="false"),
            sa.Column("can_manage_storage",      sa.Boolean(), server_default="false"),
            sa.Column("can_withdraw_storage",    sa.Boolean(), server_default="false"),
            sa.Column("can_craft_storage",       sa.Boolean(), server_default="false"),
            sa.Column("can_manage_chat",         sa.Boolean(), server_default="false"),
            sa.Column("can_manage_events",       sa.Boolean(), server_default="false"),
            sa.Column("can_manage_recruitment",  sa.Boolean(), server_default="false"),
            sa.Column("joined_at",               sa.DateTime(), nullable=False),
            sa.Column("last_active_at",          sa.DateTime(), nullable=False),
            sa.UniqueConstraint("clan_id", "user_id", name="uq_clan_member"),
        )
        op.create_index("ix_clan_members_clan_id", "clan_members", ["clan_id"])
        op.create_index("ix_clan_members_user_id", "clan_members", ["user_id"])

    # ── clan_applications ──────────────────────────────────────────────────
    if not _table_exists(bind, "clan_applications"):
        op.create_table(
            "clan_applications",
            sa.Column("id",                sa.Integer(), primary_key=True),
            sa.Column("clan_id",           sa.Integer(), sa.ForeignKey("clans.id", ondelete="CASCADE"), nullable=False),
            sa.Column("user_id",           sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("message",           sa.Text(), nullable=True),
            sa.Column("city_name",         sa.String(128), nullable=True),
            sa.Column("playstyle",         sa.String(64),  nullable=True),
            sa.Column("availability_text", sa.String(256), nullable=True),
            sa.Column("status",            sa.String(32),  nullable=False, server_default="new"),
            sa.Column("reviewed_by",       sa.Integer(),   sa.ForeignKey("users.id"), nullable=True),
            sa.Column("reviewed_at",       sa.DateTime(),  nullable=True),
            sa.Column("decision_note",     sa.Text(),      nullable=True),
            sa.Column("created_at",        sa.DateTime(),  nullable=False),
            sa.UniqueConstraint("clan_id", "user_id", name="uq_clan_application"),
        )
        op.create_index("ix_clan_applications_clan_id", "clan_applications", ["clan_id"])
        op.create_index("ix_clan_applications_user_id", "clan_applications", ["user_id"])

    # ── clan_activity_log ──────────────────────────────────────────────────
    if not _table_exists(bind, "clan_activity_log"):
        op.create_table(
            "clan_activity_log",
            sa.Column("id",            sa.Integer(), primary_key=True),
            sa.Column("clan_id",       sa.Integer(), sa.ForeignKey("clans.id", ondelete="CASCADE"), nullable=False),
            sa.Column("actor_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("action_type",   sa.String(64), nullable=False),
            sa.Column("payload_json",  sa.JSON(), nullable=False),
            sa.Column("created_at",   sa.DateTime(), nullable=False),
        )
        op.create_index("ix_clan_activity_log_clan_id", "clan_activity_log", ["clan_id"])

    # ── clan_storage_items ─────────────────────────────────────────────────
    if not _table_exists(bind, "clan_storage_items"):
        op.create_table(
            "clan_storage_items",
            sa.Column("id",                sa.Integer(), primary_key=True),
            sa.Column("clan_id",           sa.Integer(), sa.ForeignKey("clans.id", ondelete="CASCADE"), nullable=False),
            sa.Column("item_type",         sa.String(32), nullable=False),
            sa.Column("item_id",           sa.Integer(), nullable=False),
            sa.Column("quantity",          sa.Integer(), nullable=False, server_default="0"),
            sa.Column("reserved_quantity", sa.Integer(), nullable=False, server_default="0"),
            sa.Column("created_at",        sa.DateTime(), nullable=False),
            sa.Column("updated_at",        sa.DateTime(), nullable=False),
            sa.UniqueConstraint("clan_id", "item_type", "item_id", name="uq_clan_storage_item"),
            sa.CheckConstraint("quantity >= 0",          name="ck_storage_qty_positive"),
            sa.CheckConstraint("reserved_quantity >= 0", name="ck_storage_reserve_positive"),
        )
        op.create_index("ix_clan_storage_items_clan_id", "clan_storage_items", ["clan_id"])

    # ── clan_storage_transactions ──────────────────────────────────────────
    if not _table_exists(bind, "clan_storage_transactions"):
        op.create_table(
            "clan_storage_transactions",
            sa.Column("id",            sa.Integer(), primary_key=True),
            sa.Column("clan_id",       sa.Integer(), sa.ForeignKey("clans.id", ondelete="CASCADE"), nullable=False),
            sa.Column("actor_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("action_type",   sa.String(32), nullable=False),
            sa.Column("item_type",     sa.String(32), nullable=False),
            sa.Column("item_id",       sa.Integer(), nullable=False),
            sa.Column("quantity",      sa.Integer(), nullable=False),
            sa.Column("note",          sa.String(256), nullable=True),
            sa.Column("created_at",   sa.DateTime(), nullable=False),
        )
        op.create_index("ix_clan_storage_tx_clan_id", "clan_storage_transactions", ["clan_id"])

    # ── clan_meetups ───────────────────────────────────────────────────────
    if not _table_exists(bind, "clan_meetups"):
        op.create_table(
            "clan_meetups",
            sa.Column("id",            sa.Integer(), primary_key=True),
            sa.Column("clan_id",       sa.Integer(), sa.ForeignKey("clans.id", ondelete="CASCADE"), nullable=False),
            sa.Column("title",         sa.String(128), nullable=False),
            sa.Column("description",   sa.Text(), nullable=True),
            sa.Column("city_name",     sa.String(128), nullable=True),
            sa.Column("scheduled_at",  sa.DateTime(), nullable=True),
            sa.Column("created_by",    sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("status",        sa.String(32), nullable=False, server_default="scheduled"),
            sa.Column("qr_secret",     sa.String(64),  nullable=True),
            sa.Column("qr_expires_at", sa.DateTime(),  nullable=True),
            sa.Column("created_at",   sa.DateTime(), nullable=False),
        )
        op.create_index("ix_clan_meetups_clan_id", "clan_meetups", ["clan_id"])

    # ── clan_meetup_participants ───────────────────────────────────────────
    if not _table_exists(bind, "clan_meetup_participants"):
        op.create_table(
            "clan_meetup_participants",
            sa.Column("id",                  sa.Integer(), primary_key=True),
            sa.Column("meetup_id",           sa.Integer(), sa.ForeignKey("clan_meetups.id", ondelete="CASCADE"), nullable=False),
            sa.Column("user_id",             sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
            sa.Column("verified_at",         sa.DateTime(), nullable=False),
            sa.Column("verification_method", sa.String(32), server_default="qr"),
            sa.UniqueConstraint("meetup_id", "user_id", name="uq_meetup_participant"),
        )
        op.create_index("ix_clan_meetup_participants_meetup_id", "clan_meetup_participants", ["meetup_id"])

    # ── clan_chat_messages ─────────────────────────────────────────────────
    if not _table_exists(bind, "clan_chat_messages"):
        op.create_table(
            "clan_chat_messages",
            sa.Column("id",             sa.Integer(), primary_key=True),
            sa.Column("clan_id",        sa.Integer(), sa.ForeignKey("clans.id", ondelete="CASCADE"), nullable=False),
            sa.Column("sender_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
            sa.Column("message_type",   sa.String(16), nullable=False, server_default="chat"),
            sa.Column("content",        sa.Text(), nullable=False),
            sa.Column("created_at",     sa.DateTime(), nullable=False),
        )
        op.create_index("ix_clan_chat_messages_clan_id", "clan_chat_messages", ["clan_id"])
        op.create_index("ix_clan_chat_messages_created_at", "clan_chat_messages", ["created_at"])

    # ── raid_tickets ───────────────────────────────────────────────────────
    if not _table_exists(bind, "raid_tickets"):
        op.create_table(
            "raid_tickets",
            sa.Column("id",            sa.Integer(), primary_key=True),
            sa.Column("owner_type",    sa.String(16), nullable=False, server_default="user"),
            sa.Column("owner_user_id", sa.Integer(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=True),
            sa.Column("owner_clan_id", sa.Integer(), sa.ForeignKey("clans.id", ondelete="CASCADE"), nullable=True),
            sa.Column("ticket_type",   sa.String(32), nullable=False, server_default="standard"),
            sa.Column("boss_tier",     sa.Integer(), nullable=False, server_default="1"),
            sa.Column("tradable",      sa.Boolean(), server_default="true"),
            sa.Column("created_at",   sa.DateTime(), nullable=False),
            sa.Column("expires_at",   sa.DateTime(), nullable=True),
            sa.CheckConstraint(
                "(owner_user_id IS NOT NULL) OR (owner_clan_id IS NOT NULL)",
                name="ck_ticket_has_owner"
            ),
        )
        op.create_index("ix_raid_tickets_owner_user_id", "raid_tickets", ["owner_user_id"])
        op.create_index("ix_raid_tickets_owner_clan_id", "raid_tickets", ["owner_clan_id"])

    # ── raid_registrations ─────────────────────────────────────────────────
    if not _table_exists(bind, "raid_registrations"):
        op.create_table(
            "raid_registrations",
            sa.Column("id",                sa.Integer(), primary_key=True),
            sa.Column("boss_event_id",     sa.Integer(), nullable=False),
            sa.Column("registration_type", sa.String(16), nullable=False),
            sa.Column("clan_id",           sa.Integer(), sa.ForeignKey("clans.id"), nullable=True),
            sa.Column("party_leader_id",   sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
            sa.Column("created_by",        sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
            sa.Column("ticket_commitment", sa.Integer(), server_default="0"),
            sa.Column("status",            sa.String(32), nullable=False, server_default="pending"),
            sa.Column("created_at",        sa.DateTime(), nullable=False),
        )
        op.create_index("ix_raid_registrations_boss_event_id", "raid_registrations", ["boss_event_id"])

    # ── raid_tournaments ───────────────────────────────────────────────────
    if not _table_exists(bind, "raid_tournaments"):
        op.create_table(
            "raid_tournaments",
            sa.Column("id",              sa.Integer(), primary_key=True),
            sa.Column("boss_event_id",   sa.Integer(), nullable=False),
            sa.Column("status",          sa.String(32), nullable=False, server_default="pending"),
            sa.Column("winner_clan_id",  sa.Integer(), sa.ForeignKey("clans.id"), nullable=True),
            sa.Column("winner_party_id", sa.Integer(), nullable=True),
            sa.Column("created_at",     sa.DateTime(), nullable=False),
        )
        op.create_index("ix_raid_tournaments_boss_event_id", "raid_tournaments", ["boss_event_id"])

    # ── raid_tournament_matches ────────────────────────────────────────────
    if not _table_exists(bind, "raid_tournament_matches"):
        op.create_table(
            "raid_tournament_matches",
            sa.Column("id",            sa.Integer(), primary_key=True),
            sa.Column("tournament_id", sa.Integer(), sa.ForeignKey("raid_tournaments.id", ondelete="CASCADE"), nullable=False),
            sa.Column("side_a_type",   sa.String(16), nullable=False),
            sa.Column("side_a_id",     sa.Integer(), nullable=False),
            sa.Column("side_b_type",   sa.String(16), nullable=True),
            sa.Column("side_b_id",     sa.Integer(), nullable=True),
            sa.Column("winner_type",   sa.String(16), nullable=True),
            sa.Column("winner_id",     sa.Integer(), nullable=True),
            sa.Column("status",        sa.String(32), nullable=False, server_default="pending"),
            sa.Column("created_at",   sa.DateTime(), nullable=False),
        )
        op.create_index("ix_raid_tournament_matches_tournament_id", "raid_tournament_matches", ["tournament_id"])


def downgrade() -> None:
    for tbl in [
        "raid_tournament_matches", "raid_tournaments", "raid_registrations",
        "raid_tickets", "clan_chat_messages", "clan_meetup_participants",
        "clan_meetups", "clan_storage_transactions", "clan_storage_items",
        "clan_activity_log", "clan_applications", "clan_members", "clans",
    ]:
        op.drop_table(tbl)


def _table_exists(bind, name: str) -> bool:
    from sqlalchemy import inspect
    insp = inspect(bind)
    return insp.has_table(name)
