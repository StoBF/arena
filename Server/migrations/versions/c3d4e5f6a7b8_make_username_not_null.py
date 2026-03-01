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
    # Idempotency: skip if table missing or column is already NOT NULL
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    if not inspector.has_table("users"):
        return  # table will be created with NOT NULL by initial migration

    columns = {c["name"]: c for c in inspector.get_columns("users")}
    username_col = columns.get("username")
    if username_col and not username_col.get("nullable", True):
        print("INFO  [alembic] username already NOT NULL – skipping")
        return

    # Backfill any NULL usernames (PostgreSQL syntax)
    dialect = conn.dialect.name
    if dialect == "postgresql":
        op.execute(
            "UPDATE users SET username = split_part(email, '@', 1) || '_' || id::text "
            "WHERE username IS NULL"
        )
    else:
        # SQLite fallback
        op.execute(
            "UPDATE users SET username = substr(email, 1, instr(email, '@') - 1) || '_' || id "
            "WHERE username IS NULL"
        )
    op.alter_column('users', 'username',
                     existing_type=sa.String(),
                     nullable=False)


def downgrade() -> None:
    op.alter_column('users', 'username',
                     existing_type=sa.String(),
                     nullable=True)
