"""0004 - Raid Boss v2 full system

Revision ID: 0004
Revises: 0003
Create Date: 2026-03-24
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0004'
down_revision = '0003'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # 1. raid_boss_templates
    op.create_table(
        'raid_boss_templates',
        sa.Column('id',          sa.Integer,  primary_key=True),
        sa.Column('code',        sa.String(64),  unique=True, nullable=False),
        sa.Column('name',        sa.String(128), nullable=False),
        sa.Column('category',    sa.String(32),  nullable=False),
        sa.Column('archetype',   sa.String(32),  nullable=False),
        sa.Column('max_clans',   sa.Integer,  nullable=False, server_default='1'),
        sa.Column('max_heroes',  sa.Integer,  nullable=False, server_default='5'),
        sa.Column('num_phases',  sa.Integer,  nullable=False, server_default='2'),
        sa.Column('base_level',  sa.Integer,  nullable=False, server_default='1'),
        sa.Column('base_hp',     sa.Integer,  nullable=False, server_default='10000'),
        sa.Column('base_armor',  sa.Float,    nullable=False, server_default='0'),
        sa.Column('base_damage', sa.Integer,  nullable=False, server_default='500'),
        sa.Column('base_speed',  sa.Float,    nullable=False, server_default='1'),
        sa.Column('base_xp',     sa.Integer,  nullable=False, server_default='1000'),
        sa.Column('spawn_config', sa.JSON,    nullable=False, server_default='{}'),
        sa.Column('requires_qualification', sa.Boolean, nullable=False, server_default='false'),
        sa.Column('min_access_points', sa.Integer, nullable=False, server_default='0'),
        sa.Column('description', sa.Text,     nullable=True),
        sa.Column('lore',        sa.Text,     nullable=True),
    )

    # 2. raid_boss_spawns
    op.create_table(
        'raid_boss_spawns',
        sa.Column('id',          sa.Integer,  primary_key=True),
        sa.Column('template_id', sa.Integer,  sa.ForeignKey('raid_boss_templates.id'), nullable=False),
        sa.Column('status',      sa.String(32), nullable=False, server_default='pending'),
        sa.Column('opens_at',    sa.DateTime, nullable=False),
        sa.Column('closes_at',   sa.DateTime, nullable=False),
        sa.Column('started_at',  sa.DateTime, nullable=True),
        sa.Column('resolved_at', sa.DateTime, nullable=True),
        sa.Column('boss_level_snapshot', sa.Integer, nullable=False, server_default='1'),
        sa.Column('win_streak_snapshot', sa.Integer, nullable=False, server_default='0'),
        sa.Column('defeated_by_room_id', sa.Integer, nullable=True),
    )

    # 3. raid_boss_progress
    op.create_table(
        'raid_boss_progress',
        sa.Column('id',              sa.Integer, primary_key=True),
        sa.Column('template_id',     sa.Integer, sa.ForeignKey('raid_boss_templates.id'),
                  unique=True, nullable=False),
        sa.Column('current_level',   sa.Integer, nullable=False, server_default='1'),
        sa.Column('current_xp',      sa.Integer, nullable=False, server_default='0'),
        sa.Column('xp_to_next',      sa.Integer, nullable=False, server_default='5000'),
        sa.Column('rank',            sa.Integer, nullable=False, server_default='0'),
        sa.Column('evolution_stage', sa.Integer, nullable=False, server_default='0'),
        sa.Column('win_streak',      sa.Integer, nullable=False, server_default='0'),
        sa.Column('total_wins',      sa.Integer, nullable=False, server_default='0'),
        sa.Column('total_defeats',   sa.Integer, nullable=False, server_default='0'),
        sa.Column('hero_kills',      sa.Integer, nullable=False, server_default='0'),
        sa.Column('learned_resistances', sa.JSON, nullable=False, server_default='{}'),
        sa.Column('behavior_patterns',   sa.JSON, nullable=False, server_default='{}'),
        sa.Column('updated_at',      sa.DateTime, nullable=False),
    )

    # 4. raid_boss_mutations
    op.create_table(
        'raid_boss_mutations',
        sa.Column('id',          sa.Integer, primary_key=True),
        sa.Column('progress_id', sa.Integer, sa.ForeignKey('raid_boss_progress.id'), nullable=False),
        sa.Column('code',        sa.String(64),  nullable=False),
        sa.Column('name',        sa.String(128), nullable=False),
        sa.Column('description', sa.Text,        nullable=True),
        sa.Column('trigger',     sa.String(32),  nullable=False),
        sa.Column('effect',      sa.JSON,        nullable=False, server_default='{}'),
        sa.Column('is_active',   sa.Boolean,     nullable=False, server_default='true'),
        sa.Column('granted_at',  sa.DateTime,    nullable=False),
        sa.Column('expires_at',  sa.DateTime,    nullable=True),
    )

    # 5. raid_boss_phases
    op.create_table(
        'raid_boss_phases',
        sa.Column('id',             sa.Integer, primary_key=True),
        sa.Column('template_id',    sa.Integer, sa.ForeignKey('raid_boss_templates.id'), nullable=False),
        sa.Column('phase_number',   sa.Integer, nullable=False),
        sa.Column('trigger_hp_pct', sa.Float,   nullable=False),
        sa.Column('name',           sa.String(128), nullable=False),
        sa.Column('description',    sa.Text,    nullable=True),
        sa.Column('modifiers',      sa.JSON,    nullable=False, server_default='{}'),
        sa.Column('abilities',      sa.JSON,    nullable=False, server_default='[]'),
        sa.Column('arena_changes',  sa.JSON,    nullable=False, server_default='{}'),
        sa.UniqueConstraint('template_id', 'phase_number', name='uq_boss_phase'),
    )

    # 6. raid_drop_entries
    op.create_table(
        'raid_drop_entries',
        sa.Column('id',           sa.Integer, primary_key=True),
        sa.Column('template_id',  sa.Integer, sa.ForeignKey('raid_boss_templates.id'), nullable=False),
        sa.Column('item_code',    sa.String(64), nullable=True),
        sa.Column('recipe_code',  sa.String(64), nullable=True),
        sa.Column('artifact_code',sa.String(64), nullable=True),
        sa.Column('display_name', sa.String(128), nullable=False),
        sa.Column('rarity',       sa.String(32),  nullable=False),
        sa.Column('ownership',    sa.String(32),  nullable=False, server_default='personal'),
        sa.Column('drop_group',   sa.String(64),  nullable=True),
        sa.Column('base_chance',  sa.Float,       nullable=False),
        sa.Column('min_qty',      sa.Integer,     nullable=False, server_default='1'),
        sa.Column('max_qty',      sa.Integer,     nullable=False, server_default='1'),
        sa.Column('bonus_conditions', sa.JSON,    nullable=False, server_default='[]'),
        sa.Column('is_guaranteed',    sa.Boolean, nullable=False, server_default='false'),
    )

    # 7. raid_coalitions (needed before raid_rooms FK)
    op.create_table(
        'raid_coalitions',
        sa.Column('id',             sa.Integer, primary_key=True),
        sa.Column('spawn_id',       sa.Integer, sa.ForeignKey('raid_boss_spawns.id'), nullable=False),
        sa.Column('leader_clan_id', sa.Integer, sa.ForeignKey('clans.id'), nullable=False),
        sa.Column('name',           sa.String(128), nullable=True),
        sa.Column('status',         sa.String(32),  nullable=False, server_default='forming'),
        sa.Column('loot_rule',      sa.String(32),  nullable=False, server_default='contribution'),
        sa.Column('created_at',     sa.DateTime,    nullable=False),
        sa.Column('disbanded_at',   sa.DateTime,    nullable=True),
        sa.Column('cooldown_until', sa.DateTime,    nullable=True),
    )

    # 8. raid_coalition_clans
    op.create_table(
        'raid_coalition_clans',
        sa.Column('id',           sa.Integer, primary_key=True),
        sa.Column('coalition_id', sa.Integer, sa.ForeignKey('raid_coalitions.id'), nullable=False),
        sa.Column('clan_id',      sa.Integer, sa.ForeignKey('clans.id'), nullable=False),
        sa.Column('hero_slots',   sa.Integer, nullable=False, server_default='5'),
        sa.Column('accepted',     sa.Boolean, nullable=False, server_default='false'),
        sa.Column('invited_at',   sa.DateTime, nullable=False),
        sa.Column('accepted_at',  sa.DateTime, nullable=True),
        sa.UniqueConstraint('coalition_id', 'clan_id', name='uq_coalition_clan'),
    )

    # 9. raid_rooms
    op.create_table(
        'raid_rooms',
        sa.Column('id',              sa.Integer, primary_key=True),
        sa.Column('spawn_id',        sa.Integer, sa.ForeignKey('raid_boss_spawns.id'), nullable=False),
        sa.Column('coalition_id',    sa.Integer, sa.ForeignKey('raid_coalitions.id'), nullable=True),
        sa.Column('creator_user_id', sa.Integer, sa.ForeignKey('users.id'), nullable=False),
        sa.Column('creator_clan_id', sa.Integer, sa.ForeignKey('clans.id'), nullable=True),
        sa.Column('status',          sa.String(32), nullable=False, server_default='preparing'),
        sa.Column('loot_rule',       sa.String(32), nullable=False, server_default='contribution'),
        sa.Column('created_at',      sa.DateTime,   nullable=False),
        sa.Column('locked_at',       sa.DateTime,   nullable=True),
        sa.Column('started_at',      sa.DateTime,   nullable=True),
        sa.Column('finished_at',     sa.DateTime,   nullable=True),
        sa.Column('outcome',         sa.String(32), nullable=True),
        sa.Column('total_ticks',     sa.Integer,    nullable=True),
    )

    # Now add FK on spawn -> room
    op.add_column('raid_boss_spawns',
        sa.Column('_room_fk_placeholder', sa.Integer, nullable=True))
    op.drop_column('raid_boss_spawns', '_room_fk_placeholder')
    op.create_foreign_key(
        'fk_spawn_defeated_room', 'raid_boss_spawns', 'raid_rooms',
        ['defeated_by_room_id'], ['id'],
    )

    # 10. raid_participants
    op.create_table(
        'raid_participants',
        sa.Column('id',        sa.Integer, primary_key=True),
        sa.Column('room_id',   sa.Integer, sa.ForeignKey('raid_rooms.id'), nullable=False),
        sa.Column('user_id',   sa.Integer, sa.ForeignKey('users.id'),      nullable=False),
        sa.Column('hero_id',   sa.Integer, sa.ForeignKey('heroes.id'),     nullable=False),
        sa.Column('clan_id',   sa.Integer, sa.ForeignKey('clans.id'),      nullable=True),
        sa.Column('joined_at', sa.DateTime, nullable=False),
        sa.Column('is_ready',  sa.Boolean,  nullable=False, server_default='false'),
        sa.UniqueConstraint('room_id', 'hero_id', name='uq_room_hero'),
    )

    # 11. raid_access_scores
    op.create_table(
        'raid_access_scores',
        sa.Column('id',         sa.Integer, primary_key=True),
        sa.Column('clan_id',    sa.Integer, sa.ForeignKey('clans.id'), nullable=False),
        sa.Column('cycle_key',  sa.String(32), nullable=False),
        sa.Column('points',     sa.Integer, nullable=False, server_default='0'),
        sa.Column('qualified',  sa.Boolean, nullable=False, server_default='false'),
        sa.Column('updated_at', sa.DateTime, nullable=False),
        sa.UniqueConstraint('clan_id', 'cycle_key', name='uq_clan_cycle'),
    )

    # 12. raid_battle_logs
    op.create_table(
        'raid_battle_logs',
        sa.Column('id',                   sa.Integer, primary_key=True),
        sa.Column('room_id',              sa.Integer, sa.ForeignKey('raid_rooms.id'), unique=True, nullable=False),
        sa.Column('spawn_id',             sa.Integer, sa.ForeignKey('raid_boss_spawns.id'), nullable=False),
        sa.Column('outcome',              sa.String(32), nullable=False),
        sa.Column('total_ticks',          sa.Integer,    nullable=False, server_default='0'),
        sa.Column('phases_broken',        sa.Integer,    nullable=False, server_default='0'),
        sa.Column('boss_hp_remaining_pct',sa.Float,      nullable=False, server_default='1'),
        sa.Column('timeline',             sa.JSON,       nullable=False, server_default='[]'),
        sa.Column('summary',              sa.JSON,       nullable=False, server_default='{}'),
        sa.Column('created_at',           sa.DateTime,   nullable=False),
    )

    # 13. raid_contributions
    op.create_table(
        'raid_contributions',
        sa.Column('id',                  sa.Integer, primary_key=True),
        sa.Column('room_id',             sa.Integer, sa.ForeignKey('raid_rooms.id'), nullable=False),
        sa.Column('user_id',             sa.Integer, sa.ForeignKey('users.id'), nullable=False),
        sa.Column('hero_id',             sa.Integer, sa.ForeignKey('heroes.id'), nullable=False),
        sa.Column('damage_dealt',        sa.Integer, nullable=False, server_default='0'),
        sa.Column('damage_taken',        sa.Integer, nullable=False, server_default='0'),
        sa.Column('healing_done',        sa.Integer, nullable=False, server_default='0'),
        sa.Column('control_seconds',     sa.Float,   nullable=False, server_default='0'),
        sa.Column('mechanic_hits',       sa.Integer, nullable=False, server_default='0'),
        sa.Column('survival_ticks',      sa.Integer, nullable=False, server_default='0'),
        sa.Column('kills',               sa.Integer, nullable=False, server_default='0'),
        sa.Column('phases_contributed',  sa.Integer, nullable=False, server_default='0'),
        sa.Column('contribution_score',  sa.Float,   nullable=False, server_default='0'),
        sa.Column('contribution_pct',    sa.Float,   nullable=False, server_default='0'),
        sa.Column('is_mvp',              sa.Boolean, nullable=False, server_default='false'),
        sa.UniqueConstraint('room_id', 'hero_id', name='uq_contribution_hero'),
    )

    # 14. raid_reward_rolls
    op.create_table(
        'raid_reward_rolls',
        sa.Column('id',            sa.Integer, primary_key=True),
        sa.Column('battle_log_id', sa.Integer, sa.ForeignKey('raid_battle_logs.id'), nullable=False),
        sa.Column('user_id',       sa.Integer, sa.ForeignKey('users.id'),  nullable=True),
        sa.Column('clan_id',       sa.Integer, sa.ForeignKey('clans.id'),  nullable=True),
        sa.Column('drop_entry_id', sa.Integer, sa.ForeignKey('raid_drop_entries.id'), nullable=True),
        sa.Column('item_code',     sa.String(64),  nullable=True),
        sa.Column('recipe_code',   sa.String(64),  nullable=True),
        sa.Column('artifact_code', sa.String(64),  nullable=True),
        sa.Column('display_name',  sa.String(128), nullable=False),
        sa.Column('quantity',      sa.Integer,     nullable=False, server_default='1'),
        sa.Column('rarity',        sa.String(32),  nullable=False),
        sa.Column('ownership',     sa.String(32),  nullable=False, server_default='personal'),
        sa.Column('rolled_chance', sa.Float,       nullable=False, server_default='0'),
        sa.Column('is_ultra_rare', sa.Boolean,     nullable=False, server_default='false'),
        sa.Column('granted_at',    sa.DateTime,    nullable=False),
    )

    # 15. raid_boss_history
    op.create_table(
        'raid_boss_history',
        sa.Column('id',              sa.Integer, primary_key=True),
        sa.Column('template_id',     sa.Integer, sa.ForeignKey('raid_boss_templates.id'), nullable=False),
        sa.Column('spawn_id',        sa.Integer, sa.ForeignKey('raid_boss_spawns.id'), nullable=False),
        sa.Column('room_id',         sa.Integer, sa.ForeignKey('raid_rooms.id'), nullable=True),
        sa.Column('outcome',         sa.String(32), nullable=False),
        sa.Column('clan_names',      sa.JSON,       nullable=False, server_default='[]'),
        sa.Column('hero_count',      sa.Integer,    nullable=False, server_default='0'),
        sa.Column('duration_ticks',  sa.Integer,    nullable=False, server_default='0'),
        sa.Column('xp_gained',       sa.Integer,    nullable=False, server_default='0'),
        sa.Column('level_before',    sa.Integer,    nullable=False, server_default='1'),
        sa.Column('level_after',     sa.Integer,    nullable=False, server_default='1'),
        sa.Column('mutation_gained', sa.String(64), nullable=True),
        sa.Column('occurred_at',     sa.DateTime,   nullable=False),
    )


def downgrade() -> None:
    op.drop_table('raid_boss_history')
    op.drop_table('raid_reward_rolls')
    op.drop_table('raid_contributions')
    op.drop_table('raid_battle_logs')
    op.drop_table('raid_access_scores')
    op.drop_table('raid_participants')
    op.drop_foreign_key('fk_spawn_defeated_room', 'raid_boss_spawns')
    op.drop_table('raid_rooms')
    op.drop_table('raid_coalition_clans')
    op.drop_table('raid_coalitions')
    op.drop_table('raid_drop_entries')
    op.drop_table('raid_boss_phases')
    op.drop_table('raid_boss_mutations')
    op.drop_table('raid_boss_progress')
    op.drop_table('raid_boss_spawns')
    op.drop_table('raid_boss_templates')
