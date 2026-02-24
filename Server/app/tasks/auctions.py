import asyncio
import logging
from datetime import datetime
from sqlalchemy.future import select
from app.database.models.models import Auction
from app.core.enums import AuctionStatus
from app.database.session import AsyncSessionLocal
from app.services.auction import AuctionService
from app.core.redis_pubsub import publish_message

async def close_expired_auctions_task():
    """
    Background task to close expired auctions.
    CRITICAL: Uses pessimistic locking (FOR UPDATE) to prevent race conditions
    when multiple instances run concurrently.
    """
    while True:
        await asyncio.sleep(60)  # Once per minute
        async with AsyncSessionLocal() as session:
            async with session.begin():
                now = datetime.utcnow()
                
                # CRITICAL: Lock expired auctions with FOR UPDATE to prevent race
                result = await session.execute(
                    select(Auction)
                    .where(Auction.status == AuctionStatus.ACTIVE, Auction.end_time <= now)
                    .with_for_update(skip_locked=True)  # PESSIMISTIC LOCK + SKIP LOCKED
                )
                expired_auctions = result.scalars().all()
                
                if expired_auctions:
                    logging.info(f"[AUCTION] Closing {len(expired_auctions)} expired auctions.")
                
                for auction in expired_auctions:
                    logging.info(f"[AUCTION] Closing auction id={auction.id}, item_id={auction.item_id}")
                    try:
                        auction_service = AuctionService(session)
                        # close_auction is now atomic with locks (see auction.py)
                        await auction_service.close_auction(auction.id)
                        
                        # Notify participants via Redis Pub/Sub (after commit)
                        if auction.winner_id:
                            msg_win = f"You won auction #{auction.id}, price: {auction.current_price}!"
                            msg_sell = f"Your auction #{auction.id} sold. Winner id: {auction.winner_id}, price: {auction.current_price}."
                            await publish_message("private", {"type": "system", "text": msg_win}, auction.winner_id)
                            await publish_message("private", {"type": "system", "text": msg_sell}, auction.seller_id)
                            logging.info(f"[AUCTION] Notified winner id={auction.winner_id} and seller id={auction.seller_id}")
                        else:
                            msg = f"Your auction #{auction.id} ended with no bids."
                            await publish_message("private", {"type": "system", "text": msg}, auction.seller_id)
                            logging.info(f"[AUCTION] Notified seller id={auction.seller_id} about no-bids auction")
                    except Exception as e:
                        logging.error(f"[AUCTION] Error closing auction {auction.id}: {e}")
                        # Transaction will rollback, auction remains active for retry
                
                if not expired_auctions:
                    logging.info("[AUCTION] No auctions to close.") 