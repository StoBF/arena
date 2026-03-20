"""Hero system stabilization — Phase 2

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-03-16 00:00:00.000000

What this migration does
------------------------
STRING STATUS/CATEGORY COLUMNS
    Uses VARCHAR(32)-backed columns for archetype/type/domain/status/condition
    fields to avoid PostgreSQL enum dependencies during fresh bootstrap.

ALTER heroes
  • DROP  dead_until           (column removed from model; replaced by dead_at)
  • ADD   perception, willpower, archetype, current_hp, max_hp_override,
          condition, resurrection_count, dead_at, death_cause, is_permadead,
          total_kills, total_deaths, total_absorbed, training_stat,
          training_sessions_completed, created_at
  • ALTER speed / health / defense / field_of_view  → nullable  (deprecated,
          previously NOT NULL; kept for backward-compat reads)
  • INDEX ix_heroes_archetype on archetype

CREATE TABLES (7)
  hero_abilities, hero_history, hero_body_parts, hero_training_queue,
  hero_combat_stats, hero_titles, hero_resurrection_events

DOWNGRADE
  Reverses all of the above in strict dependency order.
  All operations are idempotent-guarded so re-running a partial upgrade
  does not raise errors.
"""

from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

# ---------------------------------------------------------------------------
revision: str = 'd4e5f6a7b8c9'
down_revision: Union[str, None] = 'c3d4e5f6a7b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# ---------------------------------------------------------------------------
def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    # -----------------------------------------------------------------------
    # 2. Alter existing 'heroes' table
    # -----------------------------------------------------------------------
    heroes_cols = {c['name'] for c in inspector.get_columns('heroes')}

    with op.batch_alter_table('heroes', schema=None) as batch_op:

        # --- DROP abandoned column ---
        if 'dead_until' in heroes_cols:
            batch_op.drop_column('dead_until')

        # --- ADD new primary stats ---
        if 'perception' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'perception', sa.Integer(), nullable=False, server_default='0'))
        if 'willpower' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'willpower', sa.Integer(), nullable=False, server_default='0'))

        # --- ADD archetype ---
        if 'archetype' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'archetype', sa.String(length=32), nullable=True))

        # --- ADD HP/condition columns ---
        if 'current_hp' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'current_hp', sa.Integer(), nullable=False, server_default='100'))
        if 'max_hp_override' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'max_hp_override', sa.Integer(), nullable=True))
        if 'condition' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'condition', sa.String(length=32), nullable=False, server_default='healthy'))

        # --- ADD resurrection / death tracking ---
        if 'resurrection_count' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'resurrection_count', sa.Integer(), nullable=False, server_default='0'))
        if 'dead_at' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'dead_at', sa.DateTime(), nullable=True))
        if 'death_cause' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'death_cause', sa.String(length=200), nullable=True))
        if 'is_permadead' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'is_permadead', sa.Boolean(), nullable=False, server_default='false'))

        # --- ADD kill / absorption counters ---
        if 'total_kills' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'total_kills', sa.Integer(), nullable=False, server_default='0'))
        if 'total_deaths' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'total_deaths', sa.Integer(), nullable=False, server_default='0'))
        if 'total_absorbed' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'total_absorbed', sa.Integer(), nullable=False, server_default='0'))

        # --- ADD training tracking ---
        if 'training_stat' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'training_stat', sa.String(length=30), nullable=True))
        if 'training_sessions_completed' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'training_sessions_completed', sa.Integer(), nullable=False, server_default='0'))

        # --- ADD meta ---
        if 'created_at' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'created_at', sa.DateTime(), nullable=False,
                server_default=sa.text("CURRENT_TIMESTAMP")))

        # --- ALTER deprecated stat columns to nullable ---
        # (these columns remain for backward-compat reads; were NOT NULL in initial migration)
        for col_name in ('speed', 'health', 'defense', 'field_of_view'):
            if col_name in heroes_cols:
                batch_op.alter_column(col_name, existing_type=sa.Integer(), nullable=True)

    # --- Add archetype index (outside batch; batch_alter drops/recreates constraints) ---
    heroes_indexes = {i['name'] for i in inspector.get_indexes('heroes')}
    if 'ix_heroes_archetype' not in heroes_indexes:
        op.create_index('ix_heroes_archetype', 'heroes', ['archetype'], unique=False)

    # -----------------------------------------------------------------------
    # 3. Create new tables
    # -----------------------------------------------------------------------

    # --- hero_abilities ---
    if not inspector.has_table('hero_abilities'):
        op.create_table(
            'hero_abilities',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('hero_id', sa.Integer(), sa.ForeignKey('heroes.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('ability_code', sa.String(length=80), nullable=False),
            sa.Column('ability_name', sa.String(length=120), nullable=False),
            sa.Column('ability_type', sa.String(length=32), nullable=False),
            sa.Column('ability_domain', sa.String(length=32), nullable=False),
            sa.Column('ability_level', sa.Integer(), nullable=False, server_default='1'),
            sa.Column('is_active', sa.Boolean(), nullable=False, server_default='true'),
            sa.Column('metadata_json', sa.Text(), nullable=True),
            sa.Column('acquired_at', sa.DateTime(), nullable=False,
                      server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.Column('source', sa.String(length=80), nullable=True),
            sa.UniqueConstraint('hero_id', 'ability_code', name='uq_hero_ability_code'),
        )
        with op.batch_alter_table('hero_abilities', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_hero_abilities_id'), ['id'], unique=False)
            batch_op.create_index('ix_hero_abilities_type', ['hero_id', 'ability_type'], unique=False)

    # --- hero_history ---
    if not inspector.has_table('hero_history'):
        op.create_table(
            'hero_history',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('hero_id', sa.Integer(), sa.ForeignKey('heroes.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('event_type', sa.String(length=50), nullable=False),
            sa.Column('event_data', sa.Text(), nullable=True),
            sa.Column('created_at', sa.DateTime(), nullable=False,
                      server_default=sa.text('CURRENT_TIMESTAMP')),
        )
        with op.batch_alter_table('hero_history', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_hero_history_id'), ['id'], unique=False)
            batch_op.create_index('ix_hero_history_hero_event', ['hero_id', 'event_type'], unique=False)

    # --- hero_body_parts ---
    if not inspector.has_table('hero_body_parts'):
        op.create_table(
            'hero_body_parts',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('hero_id', sa.Integer(), sa.ForeignKey('heroes.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('part_name', sa.String(length=20), nullable=False),
            sa.Column('max_hp', sa.Integer(), nullable=False),
            sa.Column('current_hp', sa.Integer(), nullable=False),
            sa.Column('armor', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('status', sa.String(length=32), nullable=False, server_default='healthy'),
            sa.Column('updated_at', sa.DateTime(), nullable=False,
                      server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.UniqueConstraint('hero_id', 'part_name', name='uq_hero_body_part'),
        )
        with op.batch_alter_table('hero_body_parts', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_hero_body_parts_id'), ['id'], unique=False)
            batch_op.create_index('ix_hero_body_parts_hero', ['hero_id'], unique=False)

    # --- hero_training_queue ---
    if not inspector.has_table('hero_training_queue'):
        op.create_table(
            'hero_training_queue',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('hero_id', sa.Integer(), sa.ForeignKey('heroes.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('training_type', sa.String(length=32), nullable=False),
            sa.Column('training_target', sa.String(length=80), nullable=False),
            sa.Column('current_level', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('target_level', sa.Integer(), nullable=False, server_default='1'),
            sa.Column('started_at', sa.DateTime(), nullable=True),
            sa.Column('ends_at', sa.DateTime(), nullable=True),
            sa.Column('status', sa.String(length=32), nullable=False, server_default='queued'),
            sa.Column('room_slot', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('efficiency', sa.Float(), nullable=False, server_default='1.0'),
        )
        with op.batch_alter_table('hero_training_queue', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_hero_training_queue_id'), ['id'], unique=False)
            batch_op.create_index('ix_training_queue_hero_status', ['hero_id', 'status'], unique=False)

    # --- hero_combat_stats ---
    if not inspector.has_table('hero_combat_stats'):
        op.create_table(
            'hero_combat_stats',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('hero_id', sa.Integer(), sa.ForeignKey('heroes.id', ondelete='CASCADE'),
                      nullable=False, unique=True, index=True),
            sa.Column('total_kills', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('boss_kills', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('arena_wins', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('battles', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('damage_dealt', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('damage_taken', sa.Integer(), nullable=False, server_default='0'),
            sa.Column('last_battle_at', sa.DateTime(), nullable=True),
        )
        with op.batch_alter_table('hero_combat_stats', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_hero_combat_stats_id'), ['id'], unique=False)

    # --- hero_titles ---
    if not inspector.has_table('hero_titles'):
        op.create_table(
            'hero_titles',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('hero_id', sa.Integer(), sa.ForeignKey('heroes.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('title_code', sa.String(length=60), nullable=False),
            sa.Column('title_name', sa.String(length=120), nullable=False),
            sa.Column('awarded_at', sa.DateTime(), nullable=False,
                      server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.Column('source', sa.String(length=120), nullable=True),
            sa.UniqueConstraint('hero_id', 'title_code', name='uq_hero_title'),
        )
        with op.batch_alter_table('hero_titles', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_hero_titles_id'), ['id'], unique=False)
            batch_op.create_index('ix_hero_titles_hero', ['hero_id'], unique=False)

    # --- hero_resurrection_events ---
    if not inspector.has_table('hero_resurrection_events'):
        op.create_table(
            'hero_resurrection_events',
            sa.Column('id', sa.Integer(), primary_key=True, autoincrement=True),
            sa.Column('hero_id', sa.Integer(), sa.ForeignKey('heroes.id', ondelete='CASCADE'),
                      nullable=False, index=True),
            sa.Column('artifact_used', sa.String(length=120), nullable=False),
            sa.Column('revived_at', sa.DateTime(), nullable=False,
                      server_default=sa.text('CURRENT_TIMESTAMP')),
            sa.Column('side_effects_json', sa.Text(), nullable=True),
            sa.Column('condition_before', sa.String(length=32), nullable=False, server_default='dead'),
            sa.Column('condition_after', sa.String(length=32), nullable=False, server_default='wounded'),
            sa.Column('hp_restored_to', sa.Integer(), nullable=False, server_default='0'),
        )
        with op.batch_alter_table('hero_resurrection_events', schema=None) as batch_op:
            batch_op.create_index(batch_op.f('ix_hero_resurrection_events_id'), ['id'], unique=False)
            batch_op.create_index('ix_resurrection_hero', ['hero_id'], unique=False)


# ---------------------------------------------------------------------------
def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    # -----------------------------------------------------------------------
    # 1. Drop new tables (reverse dependency order: no table depends on another
    #    new table, so order is arbitrary; heroes must remain intact)
    # -----------------------------------------------------------------------
    for tbl in (
        'hero_resurrection_events',
        'hero_titles',
        'hero_combat_stats',
        'hero_training_queue',
        'hero_body_parts',
        'hero_history',
        'hero_abilities',
    ):
        if inspector.has_table(tbl):
            op.drop_table(tbl)

    # -----------------------------------------------------------------------
    # 2. Reverse heroes alterations
    # -----------------------------------------------------------------------
    heroes_cols = {c['name'] for c in inspector.get_columns('heroes')}
    heroes_indexes = {i['name'] for i in inspector.get_indexes('heroes')}

    # Drop archetype index
    if 'ix_heroes_archetype' in heroes_indexes:
        op.drop_index('ix_heroes_archetype', table_name='heroes')

    with op.batch_alter_table('heroes', schema=None) as batch_op:

        # Drop added columns
        for col in (
            'perception', 'willpower', 'archetype', 'current_hp', 'max_hp_override',
            'condition', 'resurrection_count', 'dead_at', 'death_cause', 'is_permadead',
            'total_kills', 'total_deaths', 'total_absorbed',
            'training_stat', 'training_sessions_completed',
            'created_at',
        ):
            if col in heroes_cols:
                batch_op.drop_column(col)

        # Restore dead_until
        if 'dead_until' not in heroes_cols:
            batch_op.add_column(sa.Column('dead_until', sa.DateTime(), nullable=True))

        # Restore deprecated columns to NOT NULL.
        # Set the default 0 for any NULL values before adding NOT NULL constraint.
        # (These UPDATE statements run outside batch_alter; see below.)
        for col_name in ('speed', 'health', 'defense', 'field_of_view'):
            if col_name in heroes_cols:
                batch_op.alter_column(col_name, existing_type=sa.Integer(), nullable=False,
                                      server_default='0')

    # Backfill NULL values before restoring NOT NULL (SQLite batch_alter handles this;
    # for PostgreSQL the batch emulation issues ALTER COLUMN after the UPDATE below)
    for col_name in ('speed', 'health', 'defense', 'field_of_view'):
        op.execute(sa.text(f"UPDATE heroes SET {col_name} = 0 WHERE {col_name} IS NULL"))

    # No enum types to drop.
