"""Make username NOT NULL with unique constraint

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
Create Date: 2026-02-28 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c3d4e5f6a7b8'
down_revision: Union[str, None] = 'b2c3d4e5f6a7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Backfill any NULL usernames with email prefix before making NOT NULL
    op.execute(
        "UPDATE users SET username = split_part(email, '@', 1) || '_' || id::text "
        "WHERE username IS NULL"
    )
    op.alter_column('users', 'username',
                     existing_type=sa.String(),
                     nullable=False)


def downgrade() -> None:
    op.alter_column('users', 'username',
                     existing_type=sa.String(),
                     nullable=True)
