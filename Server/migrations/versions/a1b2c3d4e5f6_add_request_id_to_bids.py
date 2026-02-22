"""Add request_id field to bids table for idempotency

Revision ID: a1b2c3d4e5f6
Revises: 149a888a2550
Create Date: 2026-02-22 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'a1b2c3d4e5f6'
down_revision: Union[str, None] = '149a888a2550'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    # Add request_id column to bids table
    op.add_column(
        'bids',
        sa.Column('request_id', sa.String(), nullable=True)
    )
    # Create unique index on request_id for idempotency
    op.create_index('ix_bids_request_id', 'bids', ['request_id'], unique=True)


def downgrade() -> None:
    """Downgrade schema."""
    # Drop the unique index on request_id
    op.drop_index('ix_bids_request_id', table_name='bids')
    # Remove request_id column
    op.drop_column('bids', 'request_id')
