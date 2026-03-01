"""Add strategic database indexes for query optimization

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
Create Date: 2026-02-23 10:00:00.000000

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'b2c3d4e5f6a7'
down_revision: Union[str, None] = 'a1b2c3d4e5f6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema - Add indexes for foreign keys and query-critical columns."""
    # Idempotency: skip indexes that were already created by initial_tables
    conn = op.get_bind()
    inspector = sa.inspect(conn)

    def _index_exists(table: str, index_name: str) -> bool:
        if not inspector.has_table(table):
            return True  # table doesn't exist yet; index comes with table
        return any(i["name"] == index_name for i in inspector.get_indexes(table))

    if not _index_exists("heroes", "ix_heroes_owner_id"):
        op.create_index('ix_heroes_owner_id', 'heroes', ['owner_id'])
    if not _index_exists("auctions", "ix_auctions_seller_id"):
        op.create_index('ix_auctions_seller_id', 'auctions', ['seller_id'])
    if not _index_exists("auctions", "ix_auctions_end_time"):
        op.create_index('ix_auctions_end_time', 'auctions', ['end_time'])
    if not _index_exists("auctions", "ix_auctions_status"):
        op.create_index('ix_auctions_status', 'auctions', ['status'])
    if not _index_exists("auction_lots", "ix_auction_lots_seller_id"):
        op.create_index('ix_auction_lots_seller_id', 'auction_lots', ['seller_id'])
    if not _index_exists("auction_lots", "ix_auction_lots_end_time"):
        op.create_index('ix_auction_lots_end_time', 'auction_lots', ['end_time'])
    if not _index_exists("bids", "ix_bids_auction_id"):
        op.create_index('ix_bids_auction_id', 'bids', ['auction_id'])
    if not _index_exists("bids", "ix_bids_lot_id"):
        op.create_index('ix_bids_lot_id', 'bids', ['lot_id'])
    if not _index_exists("bids", "ix_bids_bidder_id"):
        op.create_index('ix_bids_bidder_id', 'bids', ['bidder_id'])


def downgrade() -> None:
    """Downgrade schema - Drop all added indexes."""
    
    op.drop_index('ix_heroes_owner_id', table_name='heroes')
    op.drop_index('ix_auctions_seller_id', table_name='auctions')
    op.drop_index('ix_auctions_end_time', table_name='auctions')
    op.drop_index('ix_auctions_status', table_name='auctions')
    op.drop_index('ix_auction_lots_seller_id', table_name='auction_lots')
    op.drop_index('ix_auction_lots_end_time', table_name='auction_lots')
    op.drop_index('ix_bids_auction_id', table_name='bids')
    op.drop_index('ix_bids_lot_id', table_name='bids')
    op.drop_index('ix_bids_bidder_id', table_name='bids')
