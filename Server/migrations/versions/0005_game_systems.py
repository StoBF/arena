"""0005 - Game Systems: Quests, Betting, Healing, Resurrection, Currency Shop, Alliances

Revision ID: 0005
Revises: 0004
Create Date: 2026-03-24

Changes from v1 (initial) → v2:
  - hero_heal_orders: currency_spent + premium_spent → gold_spent
  - premium_balances / premium_purchases / premium_transactions REMOVED
  - currency_purchases ADDED (Stripe → in-game gold)
  - resurrection_attempts: gold_paid column added
  - daily_quest_templates: streak_mult_per_7days REMOVED (moved to game_config.yaml)
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0005'
down_revision = '0004'
branch_labels = None
depends_on = None


def upgrade() -> None:

    # ── 1. Add columns to existing tables ──────────────────────────────────────

    op.add_column('heroes', sa.Column('resurrect_before', sa.DateTime(), nullable=True))
    op.add_column('users',  sa.Column('stripe_customer_id', sa.String(128), nullable=True))

    # ── 2. Daily Quest System ──────────────────────────────────────────────────

    op.create_table(
        'daily_quest_templates',
        sa.Column('id',          sa.Integer(), primary_key=True),
        sa.Column('code',        sa.String(64),  nullable=False, unique=True),
        sa.Column('title',       sa.String(128), nullable=False),
        sa.Column('description', sa.Text(),      nullable=False),
        sa.Column('category',    sa.String(32),  nullable=False),
        sa.Column('frequency',   sa.String(32),  nullable=False, server_default='daily'),
        sa.Column('task',        postgresql.JSONB(), nullable=False, server_default='{}'),
        sa.Column('rewards',     postgresql.JSONB(), nullable=False, server_default='[]'),
        sa.Column('xp_reward',   sa.Integer(), nullable=False, server_default='100'),
        sa.Column('is_active',   sa.Boolean(), nullable=False, server_default='true'),
    )

    op.create_table(
        'player_daily_quests',
        sa.Column('id',           sa.Integer(), primary_key=True),
        sa.Column('user_id',      sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('template_id',  sa.Integer(), sa.ForeignKey('daily_quest_templates.id'), nullable=False),
        sa.Column('cycle_key',    sa.String(32), nullable=False),
        sa.Column('progress',     sa.Integer(), nullable=False, server_default='0'),
        sa.Column('target',       sa.Integer(), nullable=False, server_default='1'),
        sa.Column('completed',    sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('claimed',      sa.Boolean(), nullable=False, server_default='false'),
        sa.Column('completed_at', sa.DateTime(), nullable=True),
        sa.Column('claimed_at',   sa.DateTime(), nullable=True),
        sa.UniqueConstraint('user_id', 'template_id', 'cycle_key', name='uq_player_quest_cycle'),
    )
    op.create_index('ix_pdq_user_cycle', 'player_daily_quests', ['user_id', 'cycle_key'])

    op.create_table(
        'player_streaks',
        sa.Column('id',                      sa.Integer(), primary_key=True),
        sa.Column('user_id',                 sa.Integer(), sa.ForeignKey('users.id'), nullable=False, unique=True),
        sa.Column('login_streak',            sa.Integer(), nullable=False, server_default='0'),
        sa.Column('last_login_date',         sa.String(12), nullable=True),
        sa.Column('max_login_streak',        sa.Integer(), nullable=False, server_default='0'),
        sa.Column('quest_streak',            sa.Integer(), nullable=False, server_default='0'),
        sa.Column('last_quest_date',         sa.String(12), nullable=True),
        sa.Column('max_quest_streak',        sa.Integer(), nullable=False, server_default='0'),
        sa.Column('total_quests_completed',  sa.Integer(), nullable=False, server_default='0'),
        sa.Column('updated_at',              sa.DateTime(), nullable=False),
    )

    # ── 3. Battle Betting Market ───────────────────────────────────────────────

    op.create_table(
        'betting_markets',
        sa.Column('id',             sa.Integer(), primary_key=True),
        sa.Column('match_type',     sa.String(32), nullable=False),
        sa.Column('match_id',       sa.String(64), nullable=False),
        sa.Column('status',         sa.String(32), nullable=False, server_default='open'),
        sa.Column('winner_ref',     sa.String(64), nullable=True),
        sa.Column('opens_at',       sa.DateTime(), nullable=False),
        sa.Column('locks_at',       sa.DateTime(), nullable=True),
        sa.Column('settled_at',     sa.DateTime(), nullable=True),
        sa.Column('house_edge_pct', sa.Float(),    nullable=False, server_default='0.05'),
        sa.Column('total_pool',     sa.Numeric(14, 2), nullable=False, server_default='0'),
        sa.Column('side_a_pool',    sa.Numeric(14, 2), nullable=False, server_default='0'),
        sa.Column('side_b_pool',    sa.Numeric(14, 2), nullable=False, server_default='0'),
        sa.UniqueConstraint('match_type', 'match_id', name='uq_market_match'),
    )
    op.create_index('ix_betting_markets_status', 'betting_markets', ['status'])

    op.create_table(
        'match_bets',
        sa.Column('id',         sa.Integer(), primary_key=True),
        sa.Column('market_id',  sa.Integer(), sa.ForeignKey('betting_markets.id'), nullable=False),
        sa.Column('bettor_id',  sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('side',       sa.String(4),  nullable=False),
        sa.Column('amount',     sa.Numeric(12, 2), nullable=False),
        sa.Column('payout',     sa.Numeric(12, 2), nullable=True),
        sa.Column('is_winner',  sa.Boolean(), nullable=True),
        sa.Column('settled_at', sa.DateTime(), nullable=True),
        sa.Column('placed_at',  sa.DateTime(), nullable=False),
        sa.UniqueConstraint('market_id', 'bettor_id', name='uq_bet_per_market'),
        sa.CheckConstraint('amount > 0', name='ck_bet_amount_positive'),
    )
    op.create_index('ix_match_bets_bettor', 'match_bets', ['bettor_id'])

    # ── 4. Hero Healing ───────────────────────────────────────────────────────

    op.create_table(
        'hero_heal_orders',
        sa.Column('id',                sa.Integer(), primary_key=True),
        sa.Column('hero_id',           sa.Integer(), sa.ForeignKey('heroes.id'), nullable=False),
        sa.Column('user_id',           sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('part_name',         sa.String(32), nullable=False),
        sa.Column('severity',          sa.String(32), nullable=False),
        sa.Column('heal_duration_sec', sa.Integer(), nullable=False),
        sa.Column('started_at',        sa.DateTime(), nullable=False),
        sa.Column('completes_at',      sa.DateTime(), nullable=False),
        sa.Column('gold_spent',        sa.Numeric(10, 2), nullable=False, server_default='0'),
        sa.Column('status',            sa.String(32), nullable=False, server_default='in_progress'),
        sa.Column('completed_at',      sa.DateTime(), nullable=True),
        sa.UniqueConstraint('hero_id', 'part_name', name='uq_heal_order_part'),
    )
    op.create_index('ix_heal_orders_status', 'hero_heal_orders', ['status', 'completes_at'])

    # ── 5. Resurrection Attempts ──────────────────────────────────────────────

    op.create_table(
        'resurrection_attempts',
        sa.Column('id',                  sa.Integer(), primary_key=True),
        sa.Column('hero_id',             sa.Integer(), sa.ForeignKey('heroes.id'), nullable=False),
        sa.Column('user_id',             sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('craft_attempted_at',  sa.DateTime(), nullable=False),
        sa.Column('craft_roll',          sa.Float(), nullable=False),
        sa.Column('craft_succeeded',     sa.Boolean(), nullable=False),
        sa.Column('craft_materials',     postgresql.JSONB(), nullable=False, server_default='[]'),
        sa.Column('gold_paid',           sa.Integer(), nullable=False, server_default='0'),
        sa.Column('used_at',             sa.DateTime(), nullable=True),
        sa.Column('resurrection_ok',     sa.Boolean(), nullable=True),
        sa.Column('notes',               sa.Text(), nullable=True),
    )
    op.create_index('ix_resurrection_hero', 'resurrection_attempts', ['hero_id'])

    # ── 6. Currency Shop (in-game gold purchased via Stripe) ──────────────────

    op.create_table(
        'currency_purchases',
        sa.Column('id',                    sa.Integer(), primary_key=True),
        sa.Column('user_id',               sa.Integer(), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('package_id',            sa.String(32),  nullable=False),
        sa.Column('stripe_payment_intent', sa.String(128), nullable=True, unique=True),
        sa.Column('stripe_charge_id',      sa.String(128), nullable=True),
        sa.Column('amount_usd',            sa.Numeric(8, 2), nullable=False),
        sa.Column('gold_granted',          sa.Integer(), nullable=False),
        sa.Column('bonus_gold',            sa.Integer(), nullable=False, server_default='0'),
        sa.Column('status',                sa.String(32), nullable=False, server_default='pending'),
        sa.Column('created_at',            sa.DateTime(), nullable=False),
        sa.Column('completed_at',          sa.DateTime(), nullable=True),
    )
    op.create_index('ix_currency_purchases_user', 'currency_purchases', ['user_id'])

    # ── 7. Alliance System ────────────────────────────────────────────────────

    op.create_table(
        'alliances',
        sa.Column('id',               sa.Integer(), primary_key=True),
        sa.Column('name',             sa.String(128), nullable=False, unique=True),
        sa.Column('tag',              sa.String(8),   nullable=False, unique=True),
        sa.Column('description',      sa.Text(), nullable=True),
        sa.Column('status',           sa.String(32), nullable=False, server_default='active'),
        sa.Column('founder_clan_id',  sa.Integer(), sa.ForeignKey('clans.id'), nullable=False),
        sa.Column('leader_clan_id',   sa.Integer(), sa.ForeignKey('clans.id'), nullable=False),
        sa.Column('max_clans',        sa.Integer(), nullable=False, server_default='5'),
        sa.Column('max_members',      sa.Integer(), nullable=False, server_default='150'),
        sa.Column('weekly_upkeep',    sa.Integer(), nullable=False, server_default='1000'),
        sa.Column('size_penalty_pct', sa.Float(),   nullable=False, server_default='0'),
        sa.Column('xp',               sa.Integer(), nullable=False, server_default='0'),
        sa.Column('rank',             sa.Integer(), nullable=False, server_default='0'),
        sa.Column('created_at',       sa.DateTime(), nullable=False),
        sa.Column('disbanded_at',     sa.DateTime(), nullable=True),
    )
    op.create_index('ix_alliances_xp', 'alliances', ['xp'])

    op.create_table(
        'alliance_members',
        sa.Column('id',           sa.Integer(), primary_key=True),
        sa.Column('alliance_id',  sa.Integer(), sa.ForeignKey('alliances.id'), nullable=False),
        sa.Column('clan_id',      sa.Integer(), sa.ForeignKey('clans.id'), nullable=False),
        sa.Column('role',         sa.String(32), nullable=False, server_default='member'),
        sa.Column('joined_at',    sa.DateTime(), nullable=False),
        sa.Column('contribution', sa.Integer(), nullable=False, server_default='0'),
        sa.UniqueConstraint('alliance_id', 'clan_id', name='uq_alliance_clan'),
    )

    op.create_table(
        'alliance_war_chests',
        sa.Column('id',             sa.Integer(), primary_key=True),
        sa.Column('alliance_id',    sa.Integer(), sa.ForeignKey('alliances.id'), nullable=False, unique=True),
        sa.Column('currency',       sa.Integer(), nullable=False, server_default='0'),
        sa.Column('resources',      postgresql.JSONB(), nullable=False, server_default='{}'),
        sa.Column('pending_income', sa.Integer(), nullable=False, server_default='0'),
        sa.Column('last_upkeep_at', sa.DateTime(), nullable=True),
        sa.Column('updated_at',     sa.DateTime(), nullable=False),
    )


def downgrade() -> None:
    op.drop_table('alliance_war_chests')
    op.drop_table('alliance_members')
    op.drop_table('alliances')
    op.drop_table('currency_purchases')
    op.drop_table('resurrection_attempts')
    op.drop_table('hero_heal_orders')
    op.drop_table('match_bets')
    op.drop_table('betting_markets')
    op.drop_table('player_streaks')
    op.drop_table('player_daily_quests')
    op.drop_table('daily_quest_templates')
    op.drop_column('users', 'stripe_customer_id')
    op.drop_column('heroes', 'resurrect_before')
