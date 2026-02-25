from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import and_, or_, func
from datetime import datetime, timedelta
from fastapi import HTTPException
import logging
from app.database.models.models import Auction, Bid, Stash, AuctionLot, AutoBid
from app.core.enums import AuctionStatus
from app.database.models.hero import Hero
from app.database.models.user import User
from app.services.base_service import BaseService
from app.core.events import emit
from sqlalchemy.orm import joinedload, selectinload
from decimal import Decimal

logger = logging.getLogger(__name__)

class AuctionService(BaseService):
    # use BaseService._txn inherited

    async def create_auction(self, seller_id: int, item_id: int, start_price: int, duration: int, quantity: int = 1):
        """
        Create item auction with atomic transaction.  Duration is capped at
        24 hours.
        """
        async with self._txn():  # Explicit transaction
            # pessimistic lock stash entry
            stash_result = await self.session.execute(
                select(Stash)
                .where(Stash.user_id == seller_id, Stash.item_id == item_id)
                .with_for_update()
            )
            stash_entry = stash_result.scalars().first()
            if not stash_entry or stash_entry.quantity < quantity:
                raise HTTPException(403, "Seller does not own enough of this item")
            if stash_entry.quantity > quantity:
                stash_entry.quantity -= quantity
            else:
                await self.session.delete(stash_entry)

            # clamp duration to 24h
            MAX_AUCTION_DURATION_HOURS = 24
            end_time = datetime.utcnow() + timedelta(hours=min(duration, MAX_AUCTION_DURATION_HOURS))
            auction = Auction(
                item_id=item_id,
                seller_id=seller_id,
                start_price=start_price,
                current_price=start_price,
                end_time=end_time,
                status=AuctionStatus.ACTIVE,
                created_at=datetime.utcnow(),
                quantity=quantity
            )
            self.session.add(auction)
            await self.session.flush()
        await self.session.refresh(auction)
        from app.core.events import emit
        # wildcard invalidation removes any paginated entries as well
        await emit("cache_invalidate", "auctions:active*")
        return auction

    async def get_auction(self, auction_id: int):
        result = await self.session.execute(select(Auction).where(Auction.id == auction_id))
        return result.scalars().first()

    async def list_auctions(self, active_only: bool = False, limit: int = 10, offset: int = 0):
        """
        List auctions with pagination support.
        
        Args:
            active_only: Filter to active auctions only
            limit: Number of items to return (max 100)
            offset: Number of items to skip
            
        Returns:
            dict with items, total, limit, offset
        """
        # Enforce max limit
        if limit > 100:
            limit = 100
        if limit < 1:
            limit = 1
        if offset < 0:
            offset = 0
        
        # Get total count
        count_query = select(func.count()).select_from(Auction)
        if active_only:
            count_query = count_query.where(and_(Auction.status == AuctionStatus.ACTIVE, Auction.end_time > datetime.utcnow()))
        total_result = await self.session.execute(count_query)
        total = total_result.scalars().first() or 0
        
        # Get paginated items
        query = select(Auction).options(joinedload(Auction.bids))
        if active_only:
            query = query.where(and_(Auction.status == AuctionStatus.ACTIVE, Auction.end_time > datetime.utcnow()))
        query = query.limit(limit).offset(offset)
        result = await self.session.execute(query)
        items = result.unique().scalars().all()
        
        return {
            "items": items,
            "total": total,
            "limit": limit,
            "offset": offset
        }

    async def cancel_auction(self, auction_id: int, seller_id: int):
        """
        Cancel auction with atomic transaction.
        All-or-nothing: auction canceled AND item returned, or neither.
        """
        async with self._txn():
            # Lock auction immediately
            auction_result = await self.session.execute(
                select(Auction)
                .where(Auction.id == auction_id)
                .with_for_update()  # LOCK
            )
            auction = auction_result.scalars().first()
            if not auction or auction.seller_id != seller_id:
                raise HTTPException(403, "Not allowed to cancel this auction")
            if auction.status != AuctionStatus.ACTIVE or auction.end_time < datetime.utcnow():
                raise HTTPException(400, "Auction is not active or already ended")
            if auction.current_price != auction.start_price:
                raise HTTPException(400, "Cannot cancel - bids already placed")
            
            # Update auction status
            auction.status = AuctionStatus.CANCELLED
            
            # Return item to stash (within transaction)
            stash_result = await self.session.execute(
                select(Stash)
                .where(Stash.user_id == seller_id, Stash.item_id == auction.item_id)
                .with_for_update()  # Lock stash too
            )
            stash_entry = stash_result.scalars().first()
            if stash_entry:
                stash_entry.quantity += auction.quantity
            else:
                self.session.add(Stash(user_id=seller_id, item_id=auction.item_id, quantity=auction.quantity))
            # Transaction commits on success
        
        from app.core.events import emit
        await emit("cache_invalidate", "auctions:active*")
        return auction

    async def close_auction(self, auction_id: int):
        """
        Close expired auction with pessimistic locking to prevent race conditions.
        Critical path: LOCK auction immediately -> verify ACTIVE -> determine winner -> transfer item/funds -> commit atomically.
        
        Safeguards:
        - SELECT ... FOR UPDATE prevents concurrent closure
        - Status verified as ACTIVE inside transaction
        - Double closure handled gracefully (logs and exits safely)
        - All transfers atomic (hero ownership + balances + items)
        """
        async with self._txn():
            # CRITICAL: Lock auction row immediately with FOR UPDATE
            # This prevents multiple workers/background tasks from processing same auction simultaneously
            logger.info(f"[AUCTION_CLOSE_START] auction_id={auction_id}")
            
            auction_result = await self.session.execute(
                select(Auction)
                .where(Auction.id == auction_id)
                .with_for_update()  # PESSIMISTIC LOCK - PREVENTS RACE CONDITION FROM CONCURRENT CLOSURE
            )
            auction = auction_result.scalars().first()
            
            # SAFEGUARD: If auction doesn't exist, exit safely
            if not auction:
                logger.warning(f"[AUCTION_CLOSE_NOT_FOUND] auction_id={auction_id}")
                raise HTTPException(404, "Auction not found")
            
            # SAFEGUARD: If auction already closed, exit safely (prevents double closure)
            if auction.status != AuctionStatus.ACTIVE:
                logger.info(f"[AUCTION_CLOSE_ALREADY_CLOSED] auction_id={auction_id} current_status={auction.status}")
                # Already closed - this is safe even if called multiple times
                return auction
            
            # Change status to FINISHED atomically (within transaction)
            auction.status = AuctionStatus.FINISHED
            logger.info(f"[AUCTION_STATUS_CHANGED] auction_id={auction_id} new_status=finished seller_id={auction.seller_id}")
            
            # Find highest bid (protected by auction row lock)
            bid_result = await self.session.execute(
                select(Bid).where(Bid.auction_id == auction_id).order_by(Bid.amount.desc()).limit(1)
            )
            highest_bid = bid_result.scalars().first()
            
            if highest_bid:
                auction.winner_id = highest_bid.bidder_id
                logger.info(f"[AUCTION_WINNER_FOUND] auction_id={auction_id} winner_id={highest_bid.bidder_id} bid_amount={highest_bid.amount}")
                
                # SAFEGUARD: Lock both users to prevent concurrent balance modifications
                # Lock order: User -> Auction (already locked) prevents deadlocks
                winner_result = await self.session.execute(
                    select(User)
                    .where(User.id == highest_bid.bidder_id)
                    .with_for_update()  # LOCK winner - prevents concurrent balance modification
                )
                winner = winner_result.scalars().first()
                
                seller_result = await self.session.execute(
                    select(User)
                    .where(User.id == auction.seller_id)
                    .with_for_update()  # LOCK seller - prevents concurrent balance modification
                )
                seller = seller_result.scalars().first()
                
                if winner and seller:
                    # Transfer funds ATOMICALLY within transaction (all-or-nothing)
                    # If any step fails AFTER this, transaction is rolled back
                    # Decimal-safe adjustments and rounding to 2 decimals
                    amt = Decimal(highest_bid.amount or 0)
                    from app.services.accounting import AccountingService

                    # Release winner reserved funds and record ledger entry
                    await AccountingService(self.session).adjust_balance(winner.id, -amt, "auction_release_reserved", reference_id=auction_id, field="reserved")

                    # Pay seller
                    await AccountingService(self.session).adjust_balance(seller.id, amt, "auction_payout", reference_id=auction_id, field="balance")
                    logger.info(f"[AUCTION_BALANCE_TRANSFER] auction_id={auction_id} winner_id={highest_bid.bidder_id} seller_id={auction.seller_id} amount={highest_bid.amount}")
                else:
                    logger.error(f"[AUCTION_USER_NOT_FOUND] auction_id={auction_id} winner_id={highest_bid.bidder_id} seller_id={auction.seller_id}")
                    raise HTTPException(500, "Failed to lock winner or seller user")
                
                # Transfer item to winner (within transaction)
                stash_result = await self.session.execute(
                    select(Stash)
                    .where(Stash.user_id == highest_bid.bidder_id, Stash.item_id == auction.item_id)
                    .with_for_update()  # Lock stash entry
                )
                stash_entry = stash_result.scalars().first()
                if stash_entry:
                    stash_entry.quantity += auction.quantity
                else:
                    self.session.add(Stash(user_id=highest_bid.bidder_id, item_id=auction.item_id, quantity=auction.quantity))
                logger.info(f"[AUCTION_ITEM_TRANSFERRED] auction_id={auction_id} winner_id={highest_bid.bidder_id} item_id={auction.item_id} quantity={auction.quantity}")
            else:
                # No bids: return item to seller (safeguard for auctions with no bidders)
                logger.info(f"[AUCTION_NO_BIDS] auction_id={auction_id} seller_id={auction.seller_id} returning_item")
                
                stash_result = await self.session.execute(
                    select(Stash)
                    .where(Stash.user_id == auction.seller_id, Stash.item_id == auction.item_id)
                    .with_for_update()  # Lock stash
                )
                stash_entry = stash_result.scalars().first()
                if stash_entry:
                    stash_entry.quantity += auction.quantity
                else:
                    self.session.add(Stash(user_id=auction.seller_id, item_id=auction.item_id, quantity=auction.quantity))
                logger.info(f"[AUCTION_ITEM_RETURNED] auction_id={auction_id} seller_id={auction.seller_id} item_id={auction.item_id} quantity={auction.quantity}")
            
            # Single commit point on transaction success (all changes atomic)
            logger.info(f"[AUCTION_CLOSE_COMPLETE] auction_id={auction_id} status=finished")
        
        from app.core.events import emit
        await emit("cache_invalidate", "auctions:active*")
        return auction

    async def close_expired_auctions(self):
        """Process any auctions or lots whose end_time has passed.

        Item auctions remain in this service, but hero lots are now managed by
        :class:`~app.services.auction_lot.AuctionLotService`.  We fetch the
        expired lot ids here and hand them off rather than keeping duplicate
        closing logic in two places.
        """
        now = datetime.utcnow()
        # item auctions
        result = await self.session.execute(
            select(Auction)
            .where(Auction.status == AuctionStatus.ACTIVE, Auction.end_time <= now)
            .with_for_update(skip_locked=True)
        )
        for auction in result.scalars().all():
            await self.close_auction(auction.id)
        # hero lots – delegate to AuctionLotService for the heavy lifting
        from app.services.auction_lot import AuctionLotService
        result = await self.session.execute(
            select(AuctionLot)
            .where(AuctionLot.status == AuctionStatus.ACTIVE, AuctionLot.end_time <= now)
            .with_for_update(skip_locked=True)
        )
        lot_ids = [lot.id for lot in result.scalars().all()]
        for lid in lot_ids:
            await AuctionLotService(self.session).close_auction_lot(lid)
        return

