"""live_battle_tables

Revision ID: 0003
Revises: 0002
Create Date: 2026-03-24
"""
from __future__ import annotations

from typing import Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0003"
down_revision: Union[str, None] = "0002"
branch_labels = None
depends_on    = None


def upgrade() -> None:
    bind = op.get_bind()
    insp = sa.inspect(bind)

    # ── battle_outcome_enum ───────────────────────────────────────────────────
    existing_enums = [e["name"] for e in insp.get_enums()]
    if "battle_outcome_enum" not in existing_enums:
        op.execute(
            "CREATE TYPE battle_outcome_enum AS ENUM "
            "('team_a_win', 'team_b_win', 'draw', 'cancelled')"
        )

    # ── live_battle_sessions ──────────────────────────────────────────────────
    if not insp.has_table("live_battle_sessions"):
        op.create_table(
            "live_battle_sessions",
            sa.Column("id",          sa.BigInteger, primary_key=True, autoincrement=True),
            sa.Column("battle_uuid", sa.String(36),  nullable=False, unique=True),
            sa.Column("map_id",      sa.String(64),  nullable=False, server_default="arena_skirmish"),
            sa.Column("mode",        sa.String(16),  nullable=False, server_default="5v5"),
            sa.Column("status",      sa.String(16),  nullable=False, server_default="pending"),
            sa.Column(
                "outcome",
                postgresql.ENUM("team_a_win", "team_b_win", "draw", "cancelled",
                                name="battle_outcome_enum", create_type=False),
                nullable=True,
            ),
            sa.Column("winner_team",     sa.String(4),  nullable=True),
            sa.Column("team_a_user_ids", sa.JSON,       nullable=False, server_default="[]"),
            sa.Column("team_b_user_ids", sa.JSON,       nullable=False, server_default="[]"),
            sa.Column("total_ticks",     sa.Integer,    nullable=False, server_default="0"),
            sa.Column("elapsed_seconds", sa.Float,      nullable=False, server_default="0"),
            sa.Column("created_at",  sa.DateTime(timezone=True), server_default=sa.func.now()),
            sa.Column("started_at",  sa.DateTime(timezone=True), nullable=True),
            sa.Column("finished_at", sa.DateTime(timezone=True), nullable=True),
        )
        op.create_index("ix_lbs_status",    "live_battle_sessions", ["status"])
        op.create_index("ix_lbs_created",   "live_battle_sessions", ["created_at"])
        op.create_index("ix_lbs_uuid",      "live_battle_sessions", ["battle_uuid"])

    # ── live_battle_event_logs ────────────────────────────────────────────────
    if not insp.has_table("live_battle_event_logs"):
        op.create_table(
            "live_battle_event_logs",
            sa.Column("id",             sa.BigInteger, primary_key=True, autoincrement=True),
            sa.Column("session_id",     sa.BigInteger,
                      sa.ForeignKey("live_battle_sessions.id", ondelete="CASCADE"),
                      nullable=False),
            sa.Column("tick",           sa.Integer,    nullable=False),
            sa.Column("event_type",     sa.String(32), nullable=False),
            sa.Column("source_hero_id", sa.Integer,    nullable=True),
            sa.Column("target_hero_id", sa.Integer,    nullable=True),
            sa.Column("position_x",     sa.Float,      nullable=True),
            sa.Column("position_z",     sa.Float,      nullable=True),
            sa.Column("payload",        sa.JSON,       nullable=False, server_default="{}"),
            sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        )
        op.create_index("ix_lbel_session",    "live_battle_event_logs", ["session_id"])
        op.create_index("ix_lbel_tick",       "live_battle_event_logs", ["tick"])
        op.create_index("ix_lbel_event_type", "live_battle_event_logs", ["event_type"])

    # ── live_battle_hero_results ──────────────────────────────────────────────
    if not insp.has_table("live_battle_hero_results"):
        op.create_table(
            "live_battle_hero_results",
            sa.Column("id",          sa.BigInteger, primary_key=True, autoincrement=True),
            sa.Column("session_id",  sa.BigInteger,
                      sa.ForeignKey("live_battle_sessions.id", ondelete="CASCADE"),
                      nullable=False),
            sa.Column("hero_id",     sa.Integer,    nullable=False),
            sa.Column("user_id",     sa.Integer,    nullable=False),
            sa.Column("team_id",     sa.String(4),  nullable=False),
            sa.Column("primary_role",sa.String(16), nullable=False),
            sa.Column("damage_dealt",    sa.Float,   nullable=False, server_default="0"),
            sa.Column("damage_taken",    sa.Float,   nullable=False, server_default="0"),
            sa.Column("kills",           sa.Integer, nullable=False, server_default="0"),
            sa.Column("control_seconds", sa.Float,   nullable=False, server_default="0"),
            sa.Column("survived",        sa.Boolean, nullable=False, server_default="false"),
            sa.Column("final_hp_pct",    sa.Float,   nullable=False, server_default="0"),
            sa.Column("final_stamina_pct", sa.Float, nullable=False, server_default="0"),
        )
        op.create_index("ix_lbhr_session", "live_battle_hero_results", ["session_id"])
        op.create_index("ix_lbhr_user",    "live_battle_hero_results", ["user_id"])


def downgrade() -> None:
    op.drop_table("live_battle_hero_results")
    op.drop_table("live_battle_event_logs")
    op.drop_table("live_battle_sessions")
    op.execute("DROP TYPE IF EXISTS battle_outcome_enum")
