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
from app.core.redis_cache import redis_cache
from sqlalchemy.orm import joinedload, selectinload
from decimal import Decimal

logger = logging.getLogger(__name__)

class AuctionService(BaseService):
    def _txn(self):
        """
        Returns a transaction context manager suitable for the current
        session state.

        If a transaction is already in progress, we must use
        ``begin_nested()`` to avoid ``InvalidRequestError`` when entering
        another ``begin()`` block.  Otherwise we start a normal
        ``begin()``.  Services can simply write ``async with self._txn():``
        and have the right behaviour regardless of whether they are called
        from another transactional function (e.g. during auction closing).
        """
        if self.session.in_transaction():
            return self.session.begin_nested()
        return self.session.begin()

    async def create_auction(self, seller_id: int, item_id: int, start_price: int, duration: int, quantity: int = 1):
        """
        Create item auction with atomic transaction.
        All-or-nothing: stash modified AND auction created, or neither.
        """
        async with self._txn():  # Explicit transaction
            # Lock stash entry immediately to prevent concurrent modifications
            stash_result = await self.session.execute(
                select(Stash)
                .where(Stash.user_id == seller_id, Stash.item_id == item_id)
                .with_for_update()  # PESSIMISTIC LOCK
            )
            stash_entry = stash_result.scalars().first()
            if not stash_entry or stash_entry.quantity < quantity:
                raise HTTPException(403, "Seller does not own enough of this item")
            
            # Reduce stash or delete entry (within transaction)
            if stash_entry.quantity > quantity:
                stash_entry.quantity -= quantity
            else:
                await self.session.delete(stash_entry)
            
            # Create auction (within same transaction)
            end_time = datetime.utcnow() + timedelta(hours=duration)
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
            await self.session.flush()  # Ensure auction gets ID
            # Transaction auto-commits on successful __aexit__
        
        await self.session.refresh(auction)
        await redis_cache.delete("auctions:active")
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
        
        await redis_cache.delete("auctions:active")
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
        
        await redis_cache.delete("auctions:active")
        return auction

    async def create_auction_lot(self, hero_id: int, seller_id: int, starting_price: int, duration: int, buyout_price: int = None):
        """
        Create hero auction lot with atomic transaction.
        Ensures hero state consistency and prevents concurrent lot creation.
        """
        async with self._txn():
            # Check for existing active lot (within transaction)
            existing = await self.session.execute(
                select(AuctionLot)
                .where(AuctionLot.hero_id == hero_id, AuctionLot.status == AuctionStatus.ACTIVE)
                .with_for_update()  # Lock existing lots for this hero
            )
            if existing.scalars().first():
                raise HTTPException(400, "Active lot for this hero already exists")
            
            # Load and LOCK hero immediately to prevent concurrent modifications
            hero_result = await self.session.execute(
                select(Hero)
                .where(Hero.id == hero_id)
                .options(selectinload(Hero.equipment_items))
                .with_for_update()  # PESSIMISTIC LOCK ON HERO
            )
            hero = hero_result.scalars().first()
            
            if not hero or hero.owner_id != seller_id:
                raise HTTPException(403, "You do not own this hero")
            if hero.is_dead or hero.is_training:
                raise HTTPException(400, "Hero is dead or in training")
            if hero.is_on_auction:
                raise HTTPException(400, "Hero is already on auction")
            if hero.equipment_items:
                raise HTTPException(400, "Remove all equipment from hero before auction")
            
            # Set hero on auction (within transaction)
            hero.is_on_auction = True
            
            # Create lot (within transaction)
            end_time = datetime.utcnow() + timedelta(hours=duration)
            lot = AuctionLot(
                hero_id=hero_id,
                seller_id=seller_id,
                starting_price=starting_price,
                current_price=starting_price,
                buyout_price=buyout_price,
                end_time=end_time,
                status=AuctionStatus.ACTIVE,
                created_at=datetime.utcnow()
            )
            self.session.add(lot)
            await self.session.flush()
            # Transaction auto-commits on success
        
        await self.session.refresh(lot)
        await redis_cache.delete("auctions:active")
        return lot

    async def get_auction_lot(self, lot_id: int):
        result = await self.session.execute(select(AuctionLot).where(AuctionLot.id == lot_id))
        return result.scalars().first()

    async def list_auction_lots(self, limit: int = 10, offset: int = 0):
        """
        List auction lots with pagination support.
        
        Args:
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
        count_query = select(func.count()).select_from(AuctionLot).where(AuctionLot.status == AuctionStatus.ACTIVE)
        total_result = await self.session.execute(count_query)
        total = total_result.scalars().first() or 0
        
        # Get paginated items
        query = select(AuctionLot).options(joinedload(AuctionLot.bids)).where(AuctionLot.status == AuctionStatus.ACTIVE)
        query = query.limit(limit).offset(offset)
        result = await self.session.execute(query)
        items = result.unique().scalars().all()
        
        return {
            "items": items,
            "total": total,
            "limit": limit,
            "offset": offset
        }

    async def delete_auction_lot(self, lot_id: int, seller_id: int):
        """
        Delete auction lot with atomic transaction.
        Prevents partial state where hero is still marked on auction.
        """
        async with self._txn():
            # Lock lot immediately
            lot_result = await self.session.execute(
                select(AuctionLot)
                .where(AuctionLot.id == lot_id)
                .with_for_update()  # LOCK LOT
            )
            lot = lot_result.scalars().first()
            if not lot or lot.seller_id != seller_id:
                raise HTTPException(403, "Not allowed to delete this lot")
            if lot.current_price != lot.starting_price:
                raise HTTPException(400, "Cannot delete lot with bids")
            
            # Lock hero and update state (within transaction)
            hero_result = await self.session.execute(
                select(Hero)
                .where(Hero.id == lot.hero_id)
                .with_for_update()  # LOCK HERO
            )
            hero = hero_result.scalars().first()
            hero.is_on_auction = False
            
            # Delete lot (within transaction)
            await self.session.delete(lot)
            # Transaction commits on success
        
        await redis_cache.delete("auctions:active")
        return lot

    async def close_auction_lot(self, lot_id: int):
        """
        Close hero auction lot with pessimistic locking to prevent race conditions.
        Critical path: LOCK lot -> LOCK hero -> verify ACTIVE -> determine winner -> transfer hero ownership + balances -> commit atomically.
        
        Safeguards:
        - SELECT ... FOR UPDATE on lot and hero prevents concurrent transfer
        - Hero ownership transfer protected by hero lock
        - Double closure handled gracefully (logs and exits safely)
        - Balance and ownership changes atomic (all-or-nothing)
        """
        async with self._txn():
            # CRITICAL: Lock lot row immediately with FOR UPDATE
            # This prevents multiple concurrent closures of same lot
            logger.info(f"[LOT_CLOSE_START] lot_id={lot_id}")
            
            lot_result = await self.session.execute(
                select(AuctionLot)
                .where(AuctionLot.id == lot_id)
                .with_for_update()  # LOCK LOT - PREVENTS CONCURRENT CLOSURE
            )
            lot = lot_result.scalars().first()
            
            # SAFEGUARD: If lot doesn't exist, exit safely
            if not lot:
                logger.warning(f"[LOT_CLOSE_NOT_FOUND] lot_id={lot_id}")
                raise HTTPException(404, "Auction lot not found")
            
            # SAFEGUARD: If lot already closed, exit safely (prevents double closure)
            if lot.status != AuctionStatus.ACTIVE:
                logger.info(f"[LOT_CLOSE_ALREADY_CLOSED] lot_id={lot_id} hero_id={lot.hero_id}")
                # Already closed - this is safe even if called multiple times
                return lot
            
            # Lock hero immediately (prevents concurrent ownership transfers)
            hero_result = await self.session.execute(
                select(Hero)
                .where(Hero.id == lot.hero_id)
                .with_for_update()  # PESSIMISTIC LOCK ON HERO - PREVENTS OWNERSHIP RACE CONDITION
            )
            hero = hero_result.scalars().first()
            if not hero:
                logger.error(f"[LOT_HERO_NOT_FOUND] lot_id={lot_id} hero_id={lot.hero_id}")
                raise HTTPException(404, "Hero not found")
            
            # Find highest bid (protected by lot row lock)
            bid_result = await self.session.execute(
                select(Bid)
                .where(Bid.lot_id == lot_id)
                .order_by(Bid.amount.desc())
                .limit(1)
            )
            highest_bid = bid_result.scalars().first()
            
            if highest_bid:
                lot.winner_id = highest_bid.bidder_id
                logger.info(f"[LOT_WINNER_FOUND] lot_id={lot_id} hero_id={lot.hero_id} winner_id={highest_bid.bidder_id} bid_amount={highest_bid.amount}")
                
                # SAFEGUARD: Lock both users for atomic balance transfer
                # Lock order: User -> Hero (already locked) prevents deadlocks
                winner_result = await self.session.execute(
                    select(User)
                    .where(User.id == highest_bid.bidder_id)
                    .with_for_update()  # LOCK WINNER - prevents concurrent balance modification
                )
                winner = winner_result.scalars().first()
                
                seller_result = await self.session.execute(
                    select(User)
                    .where(User.id == lot.seller_id)
                    .with_for_update()  # LOCK SELLER - prevents concurrent balance modification
                )
                seller = seller_result.scalars().first()
                
                if winner and seller:
                    # ATOMIC balance transfer (within transaction - all-or-nothing)
                    amt = Decimal(highest_bid.amount or 0)
                    from app.services.accounting import AccountingService
                    await AccountingService(self.session).adjust_balance(winner.id, -amt, "auction_release_reserved", reference_id=lot_id, field="reserved")
                    await AccountingService(self.session).adjust_balance(seller.id, amt, "auction_payout", reference_id=lot_id, field="balance")
                    logger.info(f"[LOT_BALANCE_TRANSFER] lot_id={lot_id} winner_id={highest_bid.bidder_id} seller_id={lot.seller_id} amount={highest_bid.amount}")
                else:
                    logger.error(f"[LOT_USER_NOT_FOUND] lot_id={lot_id} winner_id={highest_bid.bidder_id} seller_id={lot.seller_id}")
                    raise HTTPException(500, "Failed to lock winner or seller user")
                
                # SAFEGUARD: Transfer hero ownership (within transaction, hero stays locked until commit)
                # Hero lock is held throughout, preventing concurrent ownership changes
                hero.owner_id = highest_bid.bidder_id
                logger.info(f"[LOT_HERO_OWNERSHIP_TRANSFERRED] lot_id={lot_id} hero_id={lot.hero_id} new_owner_id={highest_bid.bidder_id}")
            else:
                # No bids: return hero to seller (safeguard for lots with no bidders)
                logger.info(f"[LOT_NO_BIDS] lot_id={lot_id} hero_id={lot.hero_id} seller_id={lot.seller_id} returning_hero")
            
            # Update hero and lot state (within transaction)
            hero.is_on_auction = False
            lot.status = AuctionStatus.FINISHED
            logger.info(f"[LOT_CLOSE_COMPLETE] lot_id={lot_id} hero_id={lot.hero_id} status=closed")
            # Single commit point on transaction success (all changes atomic)
        
        await redis_cache.delete("auctions:active")
        return lot