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
    
    # Hero.owner_id - Foreign key index for "get all heroes by user" queries
    op.create_index('ix_heroes_owner_id', 'heroes', ['owner_id'])
    
    # Auction.seller_id - Foreign key index for "get all auctions by seller" queries
    op.create_index('ix_auctions_seller_id', 'auctions', ['seller_id'])
    
    # Auction.end_time - Index for active auctions queries (WHERE end_time > NOW())
    op.create_index('ix_auctions_end_time', 'auctions', ['end_time'])
    
    # Auction.status - Index for status filtering (WHERE status = 'active')
    op.create_index('ix_auctions_status', 'auctions', ['status'])
    
    # AuctionLot.seller_id - Foreign key index for "get all lots by seller" queries
    op.create_index('ix_auction_lots_seller_id', 'auction_lots', ['seller_id'])
    
    # AuctionLot.end_time - Index for active lot queries (WHERE end_time > NOW())
    op.create_index('ix_auction_lots_end_time', 'auction_lots', ['end_time'])
    
    # Bid.auction_id - Foreign key index for "get all bids for auction" queries
    op.create_index('ix_bids_auction_id', 'bids', ['auction_id'])
    
    # Bid.lot_id - Foreign key index for "get all bids for lot" queries
    op.create_index('ix_bids_lot_id', 'bids', ['lot_id'])
    
    # Bid.bidder_id - Foreign key index for "get all bids by user" queries
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
