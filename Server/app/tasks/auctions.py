import asyncio
import logging
from sqlalchemy import text
from app.database.session import AsyncSessionLocal
from app.services.auction import AuctionService


# Stable advisory lock ID for global auction sweeps (must fit signed bigint range)
AUCTION_SWEEP_LOCK_ID = 941337001


async def _try_acquire_sweep_lock(session) -> bool:
    # Advisory locks are PostgreSQL-specific. In non-PostgreSQL environments
    # (e.g., SQLite tests), run without distributed lock.
    bind = session.get_bind()
    if not bind or bind.dialect.name != "postgresql":
        return True

    row = await session.execute(
        text("SELECT pg_try_advisory_lock(:lock_id)"),
        {"lock_id": AUCTION_SWEEP_LOCK_ID},
    )
    return bool(row.scalar())


async def _release_sweep_lock(session) -> None:
    bind = session.get_bind()
    if not bind or bind.dialect.name != "postgresql":
        return

    await session.execute(
        text("SELECT pg_advisory_unlock(:lock_id)"),
        {"lock_id": AUCTION_SWEEP_LOCK_ID},
    )


async def run_auction_sweep_once(session) -> bool:
    """
    Run a single sweep guarded by a distributed PostgreSQL advisory lock.

    Returns:
        True if sweep executed by this instance, False if skipped due to lock contention.
    """
    if not await _try_acquire_sweep_lock(session):
        logging.info("[AUCTION] Startup sweep skipped (lock held by another instance)")
        return False

    try:
        await AuctionService(session).close_expired_auctions()
        logging.info("[AUCTION] Startup sweep completed")
        return True
    finally:
        await _release_sweep_lock(session)

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
                    ran = await run_auction_sweep_once(session)
                    if ran:
                        logging.info("[AUCTION] Sweep completed")
                    else:
                        logging.info("[AUCTION] Sweep skipped (lock held by another instance)")
        except Exception:
            # log the stack trace but don't stop the loop
            logging.exception("[AUCTION] background sweep failed")
            # short backoff before retrying to avoid busy looping
            await asyncio.sleep(5)
