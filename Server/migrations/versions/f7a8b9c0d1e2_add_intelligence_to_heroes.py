"""Add intelligence column to heroes table

Revision ID: f7a8b9c0d1e2
Revises: e6f7a8b9c0d1
Create Date: 2026-03-20 00:00:00.000000

Root cause
----------
The initial migration (9a4b80142bda) is idempotency-guarded: if the
``users`` table already exists it returns immediately without creating any
tables.  The live database was bootstrapped from an older Hero ORM model
that used a flat stat set (strength / agility / endurance / luck / speed /
health / defense / field_of_view) and therefore did NOT include the
``intelligence`` column.

The hero-system stabilization migration (d4e5f6a7b8c9) added the other
two new S.P.E.I.A.L.W primary stats (perception, willpower) but
accidentally omitted ``intelligence``, leaving it absent from every
upgraded database.

This migration idempotently adds the missing column.

What this migration does
------------------------
ALTER heroes
  • ADD intelligence  INTEGER NOT NULL DEFAULT 0  (if not already present)

Downgrade
---------
Drops the column (safe because it was absent before this migration).
"""

from typing import Sequence, Union
from alembic import op
import sqlalchemy as sa

# ---------------------------------------------------------------------------
revision: str = 'f7a8b9c0d1e2'
down_revision: Union[str, None] = 'e6f7a8b9c0d1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


# ---------------------------------------------------------------------------
def upgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    heroes_cols = {c['name'] for c in inspector.get_columns('heroes')}

    with op.batch_alter_table('heroes', schema=None) as batch_op:
        if 'intelligence' not in heroes_cols:
            batch_op.add_column(sa.Column(
                'intelligence',
                sa.Integer(),
                nullable=False,
                server_default='0',
            ))


# ---------------------------------------------------------------------------
def downgrade() -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    heroes_cols = {c['name'] for c in inspector.get_columns('heroes')}

    with op.batch_alter_table('heroes', schema=None) as batch_op:
        if 'intelligence' in heroes_cols:
            batch_op.drop_column('intelligence')
