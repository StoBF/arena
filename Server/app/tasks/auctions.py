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

    The loop is fault-tolerant: any exception is logged and the worker keeps
    running.  This prevents a single bad query or database hiccup from killing
    the whole background task.
    """
    while True:
        try:
            await asyncio.sleep(60)  # Once per minute
            async with AsyncSessionLocal() as session:
                async with session.begin():
                    # delegate entire sweep to service method
                    await AuctionService(session).close_expired_auctions()
                    logging.info("[AUCTION] Sweep completed")
        except Exception:
            # log the stack trace but don't stop the loop
            logging.exception("[AUCTION] background sweep failed")
            # short backoff before retrying to avoid busy looping
            await asyncio.sleep(5)
