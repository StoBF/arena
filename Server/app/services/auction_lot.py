from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func
from datetime import datetime, timedelta
from fastapi import HTTPException
import logging
from app.database.models.models import AuctionLot, Bid
from sqlalchemy.orm import selectinload
from decimal import Decimal
from app.core.enums import AuctionStatus
from app.database.models.hero import Hero
from app.database.models.user import User
from app.services.base_service import BaseService
from app.core.events import emit

logger = logging.getLogger(__name__)

class AuctionLotService(BaseService):
    """Separated service containing only hero-auction methods."""

    async def create_auction_lot(self, hero_id: int, seller_id: int, starting_price: int, duration: int, buyout_price: int = None):
        async with self._txn():
            existing = await self.session.execute(
                select(AuctionLot)
                .where(AuctionLot.hero_id == hero_id, AuctionLot.status == AuctionStatus.ACTIVE)
                .with_for_update()
            )
            if existing.scalars().first():
                raise HTTPException(400, "Active lot for this hero already exists")
            hero_result = await self.session.execute(
                select(Hero)
                .where(Hero.id == hero_id)
                .options(selectinload(Hero.equipment_items))
                .with_for_update()
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
            hero.is_on_auction = True
            MAX_AUCTION_DURATION_HOURS = 24
            end_time = datetime.utcnow() + timedelta(hours=min(duration, MAX_AUCTION_DURATION_HOURS))
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
        await self.session.refresh(lot)
        await emit("cache_invalidate", "auctions:active*")
        return lot

    async def get_auction_lot(self, lot_id: int):
        result = await self.session.execute(select(AuctionLot).where(AuctionLot.id == lot_id))
        return result.scalars().first()

    async def list_auction_lots(self, limit: int = 10, offset: int = 0):
        if limit > 100:
            limit = 100
        if limit < 1:
            limit = 1
        if offset < 0:
            offset = 0
        count_query = select(func.count()).select_from(AuctionLot).where(AuctionLot.status == AuctionStatus.ACTIVE)
        total_result = await self.session.execute(count_query)
        total = total_result.scalars().first() or 0
        query = select(AuctionLot).options(joinedload(AuctionLot.bids)).where(AuctionLot.status == AuctionStatus.ACTIVE)
        query = query.limit(limit).offset(offset)
        result = await self.session.execute(query)
        items = result.unique().scalars().all()
        return {"items": items, "total": total, "limit": limit, "offset": offset}

    async def delete_auction_lot(self, lot_id: int, seller_id: int):
        async with self._txn():
            lot_result = await self.session.execute(
                select(AuctionLot)
                .where(AuctionLot.id == lot_id)
                .with_for_update()
            )
            lot = lot_result.scalars().first()
            if not lot or lot.seller_id != seller_id:
                raise HTTPException(403, "Not allowed to delete this lot")
            if lot.current_price != lot.starting_price:
                raise HTTPException(400, "Cannot delete lot with bids")
            hero_result = await self.session.execute(
                select(Hero)
                .where(Hero.id == lot.hero_id)
                .with_for_update()
            )
            hero = hero_result.scalars().first()
            hero.is_on_auction = False
            await self.session.delete(lot)
        await emit("cache_invalidate", "auctions:active*")
        return lot

    async def close_auction_lot(self, lot_id: int):
        async with self._txn():
            logger.info(f"[LOT_CLOSE_START] lot_id={lot_id}")
            lot_result = await self.session.execute(
                select(AuctionLot)
                .where(AuctionLot.id == lot_id)
                .with_for_update()
            )
            lot = lot_result.scalars().first()
            if not lot:
                logger.warning(f"[LOT_CLOSE_NOT_FOUND] lot_id={lot_id}")
                raise HTTPException(404, "Auction lot not found")
            if lot.status != AuctionStatus.ACTIVE:
                logger.info(f"[LOT_CLOSE_ALREADY_CLOSED] lot_id={lot_id} hero_id={lot.hero_id}")
                return lot
            hero_result = await self.session.execute(
                select(Hero)
                .where(Hero.id == lot.hero_id)
                .with_for_update()
            )
            hero = hero_result.scalars().first()
            if not hero:
                logger.error(f"[LOT_HERO_NOT_FOUND] lot_id={lot_id} hero_id={lot.hero_id}")
                raise HTTPException(404, "Hero not found")
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
                winner_result = await self.session.execute(
                    select(User)
                    .where(User.id == highest_bid.bidder_id)
                    .with_for_update()
                )
                winner = winner_result.scalars().first()
                seller_result = await self.session.execute(
                    select(User)
                    .where(User.id == lot.seller_id)
                    .with_for_update()
                )
                seller = seller_result.scalars().first()
                if winner and seller:
                    amt = Decimal(highest_bid.amount or 0)
                    from app.services.accounting import AccountingService
                    await AccountingService(self.session).adjust_balance(winner.id, -amt, "auction_release_reserved", reference_id=lot_id, field="reserved")
                    await AccountingService(self.session).adjust_balance(seller.id, amt, "auction_payout", reference_id=lot_id, field="balance")
                    logger.info(f"[LOT_BALANCE_TRANSFER] lot_id={lot_id} winner_id={highest_bid.bidder_id} seller_id={lot.seller_id} amount={highest_bid.amount}")
                else:
                    logger.error(f"[LOT_USER_NOT_FOUND] lot_id={lot_id} winner_id={highest_bid.bidder_id} seller_id={lot.seller_id}")
                    raise HTTPException(500, "Failed to lock winner or seller user")
                hero.owner_id = highest_bid.bidder_id
                logger.info(f"[LOT_HERO_OWNERSHIP_TRANSFERRED] lot_id={lot_id} hero_id={lot.hero_id} new_owner_id={highest_bid.bidder_id}")
            else:
                logger.info(f"[LOT_NO_BIDS] lot_id={lot_id} hero_id={lot.hero_id} seller_id={lot.seller_id} returning_hero")
            hero.is_on_auction = False
            lot.status = AuctionStatus.FINISHED
            logger.info(f"[LOT_CLOSE_COMPLETE] lot_id={lot_id} hero_id={lot.hero_id} status=closed")
        await emit("cache_invalidate", "auctions:active*")
        return lot
