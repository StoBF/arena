"""Align auction status columns with ORM text storage.

Revision ID: e6f7a8b9c0d1
Revises: d4e5f6a7b8c9
Create Date: 2026-03-18 00:00:00.000000

This migration is intentionally idempotent. It fixes two production-compat
issues without inventing new schema names:

1. Ensures `auctions.status` and `auction_lots.status` exist.
2. Aligns both columns to VARCHAR(32) with lowercase string values such as
   `active`, matching current ORM and query behavior.
"""

from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'e6f7a8b9c0d1'
down_revision: Union[str, None] = 'd4e5f6a7b8c9'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


STATUS_DEFAULT = 'active'


def _index_exists(inspector: sa.Inspector, table_name: str, index_name: str) -> bool:
    if not inspector.has_table(table_name):
        return False
    return any(index['name'] == index_name for index in inspector.get_indexes(table_name))


def _ensure_status_column(table_name: str, index_name: str) -> None:
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    if not inspector.has_table(table_name):
        return

    columns = {column['name']: column for column in inspector.get_columns(table_name)}
    dialect = conn.dialect.name

    if 'status' not in columns:
        with op.batch_alter_table(table_name, schema=None) as batch_op:
            batch_op.add_column(sa.Column('status', sa.String(length=32), nullable=False, server_default=STATUS_DEFAULT))
        columns = {column['name']: column for column in sa.inspect(conn).get_columns(table_name)}

    existing_type = columns['status']['type']
    nullable = columns['status'].get('nullable', True)

    if dialect == 'postgresql':
        op.alter_column(
            table_name,
            'status',
            existing_type=existing_type,
            type_=sa.String(length=32),
            existing_nullable=nullable,
            postgresql_using='lower(status::text)',
        )
    elif not isinstance(existing_type, sa.String):
        with op.batch_alter_table(table_name, schema=None) as batch_op:
            batch_op.alter_column(
                'status',
                existing_type=existing_type,
                type_=sa.String(length=32),
                existing_nullable=nullable,
            )

    conn.execute(sa.text(f"UPDATE {table_name} SET status = :default WHERE status IS NULL"), {'default': STATUS_DEFAULT})
    conn.execute(sa.text(f"UPDATE {table_name} SET status = lower(CAST(status AS VARCHAR(32)))"))

    with op.batch_alter_table(table_name, schema=None) as batch_op:
        batch_op.alter_column(
            'status',
            existing_type=sa.String(length=32),
            nullable=False,
            server_default=STATUS_DEFAULT,
        )

    if not _index_exists(sa.inspect(conn), table_name, index_name):
        op.create_index(index_name, table_name, ['status'], unique=False)


def upgrade() -> None:
    _ensure_status_column('auctions', 'ix_auctions_status')
    _ensure_status_column('auction_lots', 'ix_auction_lots_status')


def downgrade() -> None:
    # Keep downgrade conservative: revert only nullability/default tweaks.
    conn = op.get_bind()
    inspector = sa.inspect(conn)
    for table_name in ('auctions', 'auction_lots'):
        if not inspector.has_table(table_name):
            continue
        columns = {column['name']: column for column in inspector.get_columns(table_name)}
        if 'status' not in columns:
            continue
        with op.batch_alter_table(table_name, schema=None) as batch_op:
            batch_op.alter_column(
                'status',
                existing_type=sa.String(length=32),
                nullable=True,
                server_default=None,
            )