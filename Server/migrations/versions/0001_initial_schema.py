"""Initial schema — all tables from current SQLAlchemy models

Creates every table registered in Base.metadata using ``create_all()``.
This replaces the previous 11-migration chain with a single idempotent
migration that always reflects the current model definitions.

Tables created (≈55):
  users, heroes, hero_stats, hero_generation_layers, hero_tags,
  skills_catalog, hero_skills, hero_skill_effects, hero_hidden_traits,
  hero_body_parts, hero_combat_stats, hero_titles,
  hero_resurrection_events, hero_history,
  equipment, auction_lots, battle_queue, battle_bets,
  items, stash, auctions, bids, auto_bids, perks,
  announcements, chat_messages, offline_messages,
  pvp_matches, pvp_battle_logs, leaderboard,
  mob_templates, boss_perks, mob_perks, raid_arena_instances,
  pve_battle_logs, raid_bosses, raid_drops, recipe_drops,
  craft_recipes, craft_recipe_resources, crafted_items, craft_queue,
  resources, tournament_templates, tournament_instances,
  event_definitions, event_instances, currency_transactions,
  quantum_heroes, quantum_equipment, quantum_resources,
  quantum_recipes, quantum_crafted_items

Revision ID: 0001
Revises: —
Create Date: 2026-03-22
"""
from typing import Sequence, Union

from alembic import op

# Base.metadata already has every table registered (env.py imports
# app.database.models which triggers all model modules).
from app.database.base import Base


# revision identifiers, used by Alembic.
revision: str = "0001"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create all tables from current model definitions.

    ``checkfirst=True`` makes this idempotent — tables that already exist
    are silently skipped.
    """
    bind = op.get_bind()
    Base.metadata.create_all(bind=bind, checkfirst=True)


def downgrade() -> None:
    """Drop every model-defined table (reverse of upgrade)."""
    bind = op.get_bind()
    Base.metadata.drop_all(bind=bind, checkfirst=True)
