from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database.models.models import Bid, Auction, AuctionLot, AutoBid
from app.core.enums import AuctionStatus
from app.database.models.user import User
from app.database.models.hero import Hero
from sqlalchemy import and_, func
from fastapi import HTTPException
from app.services.base_service import BaseService
from datetime import datetime
from decimal import Decimal

class BidService(BaseService):
    async def _create_bid(self, lot_id: int, bidder_id: int, bid_amount: int):
        """
        DEPRECATED: Use place_lot_bid() instead.
        This helper method kept for backward compatibility.
        """
        return await self.place_lot_bid(bidder_id, lot_id, bid_amount)

    async def get_bid(self, bid_id: int):
        """Отримати ставку за id."""
        result = await self.session.execute(select(Bid).where(Bid.id == bid_id))
        return result.scalars().first()

    async def list_bids(self, limit: int = 10, offset: int = 0):
        """
        List bids with pagination support.
        
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
        count_query = select(func.count()).select_from(Bid)
        total_result = await self.session.execute(count_query)
        total = total_result.scalars().first() or 0
        
        # Get paginated items
        query = select(Bid).limit(limit).offset(offset)
        result = await self.session.execute(query)
        items = result.scalars().all()
        
        return {
            "items": items,
            "total": total,
            "limit": limit,
            "offset": offset
        }

    async def delete_bid(self, bid_id: int):
        """Видалити ставку."""
        bid = await self.get_bid(bid_id)
        if bid:
            await self.session.delete(bid)
            await self.commit_or_rollback()
        return bid

    async def place_bid(self, bidder_id: int, auction_id: int, amount: Decimal, request_id: str = None):
        """
        Place bid on item auction with atomic transaction and row-level locking.
        Supports idempotent requests via request_id UUID.

        Prevents race conditions on user balance/reserved and auction updates.
        If same request_id is provided again, returns previous result without duplicate charge.
        """
        # IDEMPOTENCY CHECK: If request_id provided, check if bid already exists
        if request_id:
            existing_result = await self.session.execute(
                select(Bid).where(Bid.request_id == request_id)
            )
            existing_bid = existing_result.scalars().first()
            if existing_bid:
                # Return previous result (idempotent behavior)
                print(f"[BID_IDEMPOTENT] Returning previous bid {existing_bid.id} for request_id {request_id}")
                return existing_bid

        # Use BaseService._txn() for correct nested behaviour
        async with self._txn():
            # Ensure amount is Decimal for safe arithmetic
            amount = Decimal(amount)

            # Lock auction immediately (prevents concurrent modifications)
            auction_result = await self.session.execute(
                select(Auction)
                .where(Auction.id == auction_id, Auction.status == AuctionStatus.ACTIVE)
                .with_for_update()  # PESSIMISTIC LOCK ON AUCTION
            )
            auction = auction_result.scalars().first()
            if not auction or auction.end_time < datetime.utcnow():
                raise HTTPException(400, "Auction is not active")
            if auction.seller_id == bidder_id:
                raise HTTPException(400, "Seller cannot bid on own auction")
            # Ensure Decimal comparison (auction.current_price is Numeric/Decimal)
            if amount <= (auction.current_price or Decimal('0.00')):
                raise HTTPException(400, "Bid must be higher than current price")

            # Lock bidder user row to prevent concurrent balance modifications
            user_result = await self.session.execute(
                select(User)
                .where(User.id == bidder_id)
                .with_for_update()  # PESSIMISTIC LOCK ON USER - PREVENTS RACE CONDITION
            )
            user = user_result.scalars().first()
            if not user or (user.balance - user.reserved) < amount:
                raise HTTPException(400, "Insufficient funds")

            # Release previous bidder's reserved funds (if not same bidder)
            prev_bid_result = await self.session.execute(
                select(Bid)
                .where(Bid.auction_id == auction_id)
                .order_by(Bid.amount.desc())
                .limit(1)
            )
            prev_bid = prev_bid_result.scalars().first()
            if prev_bid and prev_bid.bidder_id != bidder_id:
                # Lock previous bidder to update reserve
                prev_user_result = await self.session.execute(
                    select(User)
                    .where(User.id == prev_bid.bidder_id)
                    .with_for_update()  # LOCK PREVIOUS BIDDER
                )
                prev_user = prev_user_result.scalars().first()
                if prev_user:
                    # Decimal-safe subtraction with ledger entry
                    from app.services.accounting import AccountingService
                    await AccountingService(self.session).adjust_balance(prev_user.id, -(prev_bid.amount or Decimal('0.00')), "bid_release_reserved", reference_id=auction_id, field="reserved")

            # Update current bidder reserve (ledgered)
            from app.services.accounting import AccountingService
            await AccountingService(self.session).adjust_balance(user.id, amount, "bid_reserve", reference_id=auction_id, field="reserved")

            # Create bid with request_id for idempotency
            bid = Bid(
                request_id=request_id,  # Store idempotency key
                auction_id=auction_id,
                bidder_id=bidder_id,
                amount=amount,
                created_at=datetime.utcnow()
            )
            self.session.add(bid)

            # Update auction
            # Store price rounded to 2 decimals
            auction.current_price = amount.quantize(Decimal('0.01'))
            auction.winner_id = bidder_id

            await self.session.flush()
            await self.session.refresh(bid)
        # transaction complete; clear related caches
        from app.core.events import emit
        await emit("cache_invalidate", "auctions:active*")
        return bid

    async def place_lot_bid(self, bidder_id: int, lot_id: int, amount: Decimal, request_id: str = None):
        """
        Place bid on hero auction lot with atomic transaction and row-level locking.
        Supports idempotent requests via request_id UUID.
        
        Prevents race conditions on user balance/reserved and lot updates.
        If same request_id is provided again, returns previous result without duplicate charge.
        """
        # IDEMPOTENCY CHECK: If request_id provided, check if bid already exists
        if request_id:
            existing_result = await self.session.execute(
                select(Bid).where(Bid.request_id == request_id)
            )
            existing_bid = existing_result.scalars().first()
            if existing_bid:
                # Return previous result (idempotent behavior)
                print(f"[BID_IDEMPOTENT] Returning previous bid {existing_bid.id} for request_id {request_id}")
                return existing_bid

        async with self._txn():
            # Lock lot immediately
            lot_result = await self.session.execute(
                select(AuctionLot)
                .where(AuctionLot.id == lot_id, AuctionLot.status == AuctionStatus.ACTIVE)
                .with_for_update()  # PESSIMISTIC LOCK ON LOT
            )
            lot = lot_result.scalars().first()
            if not lot or lot.end_time < datetime.utcnow():
                raise HTTPException(400, "Auction lot is not active")
            if lot.seller_id == bidder_id:
                raise HTTPException(400, "Seller cannot bid on own lot")
            if amount <= (lot.current_price or Decimal('0.00')):
                raise HTTPException(400, "Bid must be higher than current price")

            # Lock bidder user row to prevent concurrent balance modifications
            user_result = await self.session.execute(
                select(User)
                .where(User.id == bidder_id)
                .with_for_update()  # PESSIMISTIC LOCK ON USER - PREVENTS RACE CONDITION
            )
            user = user_result.scalars().first()
            if not user or (user.balance - user.reserved) < amount:
                raise HTTPException(400, "Insufficient funds")

            # Release previous bidder's reserved funds (if not same bidder)
            prev_bid_result = await self.session.execute(
                select(Bid)
                .where(Bid.lot_id == lot_id)
                .order_by(Bid.amount.desc())
                .limit(1)
            )
            prev_bid = prev_bid_result.scalars().first()
            if prev_bid and prev_bid.bidder_id != bidder_id:
                # Lock previous bidder to update reserve
                prev_user_result = await self.session.execute(
                    select(User)
                    .where(User.id == prev_bid.bidder_id)
                    .with_for_update()  # LOCK PREVIOUS BIDDER
                )
                prev_user = prev_user_result.scalars().first()
                if prev_user:
                    from app.services.accounting import AccountingService
                    await AccountingService(self.session).adjust_balance(prev_user.id, -(prev_bid.amount or Decimal('0.00')), "bid_release_reserved", reference_id=lot_id, field="reserved")

            # Update current bidder reserve (ledgered)
            from app.services.accounting import AccountingService
            await AccountingService(self.session).adjust_balance(user.id, amount, "bid_reserve", reference_id=lot_id, field="reserved")

            # Create bid with request_id for idempotency
            bid = Bid(
                request_id=request_id,  # Store idempotency key
                lot_id=lot_id,
                bidder_id=bidder_id,
                amount=amount,
                created_at=datetime.utcnow()
            )
            self.session.add(bid)

            # Update lot - round to 2 decimals
            lot.current_price = amount.quantize(Decimal('0.01'))
            lot.winner_id = bidder_id

            await self.session.flush()
            await self.session.refresh(bid)
        # transaction complete; invalidate both caches
        from app.core.events import emit
        await emit("cache_invalidate", "auctions:active*")
        await emit("cache_invalidate", "auctions:active_lots*")
        return bid

    async def set_auto_bid(self, user_id: int, auction_id: int = None, lot_id: int = None, max_amount: Decimal = Decimal('0.00')):
        """
        Set or update autobid with atomic transaction and user lock.
        Prevents race conditions on user reserve balance.
        """
        # choose a transaction context depending on whether one is already active
        if self.session.in_transaction():
            tx = self.session.begin_nested()
        else:
            tx = self.session.begin()
        async with tx:
            # Lock user immediately to prevent concurrent reserve modifications
            user_result = await self.session.execute(
                select(User)
                .where(User.id == user_id)
                .with_for_update()  # PESSIMISTIC LOCK ON USER
            )
            user = user_result.scalars().first()
            if not user:
                raise HTTPException(404, "User not found")
            
            # Validate funds are available (after locking)
            if (user.balance - user.reserved) < max_amount:
                raise HTTPException(400, "Insufficient funds for autobid reserve")
            
            # Find existing autobid (if any)
            autobid = None
            if auction_id:
                autobid_result = await self.session.execute(
                    select(AutoBid)
                    .where(AutoBid.auction_id == auction_id, AutoBid.user_id == user_id)
                    .with_for_update()  # Lock existing autobid
                )
                autobid = autobid_result.scalars().first()
            elif lot_id:
                autobid_result = await self.session.execute(
                    select(AutoBid)
                    .where(AutoBid.lot_id == lot_id, AutoBid.user_id == user_id)
                    .with_for_update()  # Lock existing autobid
                )
                autobid = autobid_result.scalars().first()
            
            if autobid:
                # Update existing autobid (account for difference)
                old_reserve = autobid.max_amount or Decimal('0.00')
                new_reserve = max_amount
                # Adjust reserved amount via ledger
                from app.services.accounting import AccountingService
                diff = new_reserve - old_reserve
                if diff != Decimal('0.00'):
                    await AccountingService(self.session).adjust_balance(user.id, diff, "autobid_reserve_update", reference_id=None, field="reserved")
                autobid.max_amount = new_reserve.quantize(Decimal('0.01'))
            else:
                # Create new autobid
                autobid = AutoBid(
                    auction_id=auction_id,
                    lot_id=lot_id,
                    user_id=user_id,
                    max_amount=max_amount.quantize(Decimal('0.01'))
                )
                self.session.add(autobid)
                from app.services.accounting import AccountingService
                await AccountingService(self.session).adjust_balance(user.id, max_amount, "autobid_reserve", reference_id=None, field="reserved")
            
            await self.session.flush()
            # Transaction auto-commits on success
        
        await self.session.refresh(autobid)
        return autobid