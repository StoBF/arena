"""
Production-grade distributed locking using Redis.

Provides both context manager and manual lock/unlock patterns for:
- Global operations (sweep task coordination)
- Per-resource operations (auction closing, hero transfers)

Safety guarantees:
- Only the lock holder (UUID) can release
- TTL prevents deadlocks on instance crash
- Async-safe with minimal Redis footprint
- Lua script ensures atomic unlock+value verification
"""

import asyncio
import logging
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timedelta
from typing import AsyncGenerator, Optional, Tuple

from redis.asyncio import Redis
from redis.exceptions import RedisError

logger = logging.getLogger(__name__)


class DistributedLock:
    """
    Redis-backed distributed lock with crash safety.

    Usage (context manager):
        lock = DistributedLock(redis_client, "resource:key", ttl=60)
        async with lock.acquire():
            # Critical section - guaranteed exclusive access
            await do_something()
        # Lock automatically released

    Usage (manual):
        lock = DistributedLock(redis_client, "resource:key", ttl=60)
        lock_acquired = await lock.acquire()
        if lock_acquired:
            try:
                # Critical section
                await do_something()
            finally:
                await lock.release()
        else:
            # Another instance holds the lock
            logger.info("Could not acquire lock, skipping...")
    """

    # Lua script for atomic unlock: delete key only if value matches
    # Returns 1 if deleted, 0 if key/value mismatch
    UNLOCK_SCRIPT = """
    if redis.call("GET", KEYS[1]) == ARGV[1] then
        return redis.call("DEL", KEYS[1])
    else
        return 0
    end
    """

    def __init__(
        self,
        redis_client: Redis,
        key: str,
        ttl: int = 60,
        auto_renewal: bool = False,
        renewal_interval: int = None,
    ):
        """
        Initialize a distributed lock.

        Args:
            redis_client: Redis async client instance
            key: Lock key (e.g., "dist_lock:auction_sweep")
            ttl: Lock time-to-live in seconds (default 60)
                 - Must cover expected operation duration
                 - Should be 2-5x normal operation time
                 - Auto-expires on crash
            auto_renewal: If True, renew lock periodically (for long operations)
            renewal_interval: Renew every N seconds (default: ttl//3)
        """
        self.redis = redis_client
        self.key = key
        self.ttl = ttl
        self.auto_renewal = auto_renewal
        self.renewal_interval = renewal_interval or max(ttl // 3, 5)

        # Unique lock value - prevents accidental release by other processes
        self._lock_value = str(uuid.uuid4())
        self._acquired = False
        self._renewal_task: Optional[asyncio.Task] = None

    async def acquire(self, blocking: bool = False, timeout: float = None) -> bool:
        """
        Acquire the lock.

        Args:
            blocking: If True, wait until lock is available (not recommended for production)
            timeout: Timeout in seconds (only if blocking=True)

        Returns:
            True if lock acquired, False otherwise
        """
        logger.debug(f"[LOCK_ACQUIRE_ATTEMPT] key={self.key} value={self._lock_value[:8]}...")

        if blocking and timeout:
            # Exponential backoff for blocking acquire
            start = datetime.utcnow()
            backoff = 0.1
            while True:
                try:
                    acquired = await self.redis.set(
                        self.key,
                        self._lock_value,
                        nx=True,  # Only set if key doesn't exist
                        ex=self.ttl,  # Expire after TTL seconds
                    )
                    if acquired:
                        self._acquired = True
                        logger.info(
                            f"[LOCK_ACQUIRED] key={self.key} "
                            f"value={self._lock_value[:8]}... ttl={self.ttl}s"
                        )
                        if self.auto_renewal:
                            self._renewal_task = asyncio.create_task(self._renew_loop())
                        return True

                    # Check timeout
                    elapsed = (datetime.utcnow() - start).total_seconds()
                    if elapsed > timeout:
                        logger.warning(
                            f"[LOCK_TIMEOUT] key={self.key} waited {elapsed:.1f}s, giving up"
                        )
                        return False

                    # Backoff before retry
                    await asyncio.sleep(min(backoff, timeout - elapsed))
                    backoff *= 1.5

                except RedisError as e:
                    logger.error(f"[LOCK_ERROR] key={self.key} error={e}")
                    return False
        else:
            # Non-blocking acquire
            try:
                acquired = await self.redis.set(
                    self.key,
                    self._lock_value,
                    nx=True,
                    ex=self.ttl,
                )
                if acquired:
                    self._acquired = True
                    logger.info(
                        f"[LOCK_ACQUIRED] key={self.key} "
                        f"value={self._lock_value[:8]}... ttl={self.ttl}s"
                    )
                    if self.auto_renewal:
                        self._renewal_task = asyncio.create_task(self._renew_loop())
                    return True
                else:
                    logger.debug(f"[LOCK_HELD] key={self.key} (another instance holds lock)")
                    return False
            except RedisError as e:
                logger.error(f"[LOCK_ERROR] key={self.key} error={e}")
                return False

    async def release(self) -> bool:
        """
        Release the lock safely.

        Uses Lua script to verify lock value matches before deletion.
        Only the lock holder (with matching UUID) can release.

        Returns:
            True if lock was released, False if mismatch/error
        """
        if not self._acquired:
            logger.debug(f"[LOCK_NOT_HELD] key={self.key} (never acquired)")
            return False

        # Cancel renewal task if active
        if self._renewal_task:
            self._renewal_task.cancel()
            try:
                await self._renewal_task
            except asyncio.CancelledError:
                pass
            self._renewal_task = None

        try:
            # Use Lua script for atomic unlock
            result = await self.redis.eval(
                self.UNLOCK_SCRIPT,
                1,  # Number of keys
                self.key,  # KEYS[1]
                self._lock_value,  # ARGV[1]
            )

            if result == 1:
                self._acquired = False
                logger.info(f"[LOCK_RELEASED] key={self.key} value={self._lock_value[:8]}...")
                return True
            else:
                # Lock value mismatch - another instance overwrote our lock
                logger.warning(
                    f"[LOCK_RELEASE_FAILED] key={self.key} "
                    f"value_mismatch (another instance acquired lock)"
                )
                self._acquired = False
                return False

        except RedisError as e:
            logger.error(f"[LOCK_RELEASE_ERROR] key={self.key} error={e}")
            self._acquired = False
            return False

    async def extend(self, additional_ttl: int = None) -> bool:
        """
        Extend lock TTL if still held by this instance.

        Useful for long-running operations that need more time.

        Args:
            additional_ttl: Additional time in seconds (default: self.ttl)

        Returns:
            True if extended, False if lock lost or error
        """
        if not self._acquired:
            return False

        new_ttl = additional_ttl or self.ttl
        try:
            # Use Lua to ensure value matches before extending
            script = """
            if redis.call("GET", KEYS[1]) == ARGV[1] then
                return redis.call("EXPIRE", KEYS[1], ARGV[2])
            else
                return 0
            end
            """
            result = await self.redis.eval(
                script,
                1,
                self.key,
                self._lock_value,
                new_ttl,
            )

            if result == 1:
                logger.debug(f"[LOCK_EXTENDED] key={self.key} new_ttl={new_ttl}s")
                return True
            else:
                logger.warning(f"[LOCK_LOST] key={self.key} (value mismatch on extend)")
                self._acquired = False
                return False

        except RedisError as e:
            logger.error(f"[LOCK_EXTEND_ERROR] key={self.key} error={e}")
            return False

    @asynccontextmanager
    async def context(self, blocking: bool = False) -> AsyncGenerator[bool, None]:
        """
        Async context manager for easy lock usage.

        Usage:
            async with lock.context() as acquired:
                if acquired:
                    # Do critical work
                    pass

        Yields:
            True if lock acquired, False otherwise
        """
        acquired = await self.acquire(blocking=blocking)
        try:
            yield acquired
        finally:
            if acquired:
                await self.release()

    async def _renew_loop(self):
        """
        Internal: Periodically renew lock for long-running operations.

        Runs if auto_renewal=True. Cancels itself if lock is lost.
        """
        try:
            while self._acquired:
                await asyncio.sleep(self.renewal_interval)
                if not await self.extend():
                    logger.warning(f"[LOCK_RENEWAL_FAILED] key={self.key} (lock lost)")
                    break
        except asyncio.CancelledError:
            logger.debug(f"[LOCK_RENEWAL_CANCELLED] key={self.key}")
            raise

    # Allow usage with 'async with' directly
    async def __aenter__(self):
        acquired = await self.acquire()
        if not acquired:
            raise RuntimeError(f"Failed to acquire lock: {self.key}")
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.release()
        return False


class DistributedLockManager:
    """
    Simple factory/manager for creating locks with consistent configuration.

    Useful for centralizing lock TTL settings and Redis client management.
    """

    def __init__(self, redis_client: Redis):
        self.redis = redis_client

    def create_sweep_lock(self, operation: str = "auction_sweep") -> DistributedLock:
        """
        Create a global operation lock (e.g., for sweep tasks).

        TTL: 90 seconds (covers sweep + processing of several hundred auctions)
        """
        return DistributedLock(
            self.redis,
            f"dist_lock:{operation}",
            ttl=90,
            auto_renewal=False,
        )

    def create_auction_lock(self, auction_id: int) -> DistributedLock:
        """
        Create a per-auction lock.

        TTL: 120 seconds (covers full close transaction with retries)
        """
        return DistributedLock(
            self.redis,
            f"dist_lock:auction:{auction_id}",
            ttl=120,
            auto_renewal=False,
        )

    def create_lot_lock(self, lot_id: int) -> DistributedLock:
        """
        Create a per-lot lock.

        TTL: 120 seconds (covers full close transaction)
        """
        return DistributedLock(
            self.redis,
            f"dist_lock:auction_lot:{lot_id}",
            ttl=120,
            auto_renewal=False,
        )

    def create_user_lock(self, user_id: int) -> DistributedLock:
        """
        Create a per-user lock (for balance-sensitive operations).

        TTL: 30 seconds (prevents balance race conditions)
        """
        return DistributedLock(
            self.redis,
            f"dist_lock:user:{user_id}",
            ttl=30,
            auto_renewal=False,
        )

    def create_custom_lock(
        self, resource_key: str, ttl: int = 60, auto_renewal: bool = False
    ) -> DistributedLock:
        """
        Create a custom lock for any resource.

        Args:
            resource_key: Key name (e.g., "transfer:hero:123")
            ttl: Time-to-live in seconds
            auto_renewal: Enable periodic renewal for long operations
        """
        return DistributedLock(
            self.redis, f"dist_lock:{resource_key}", ttl=ttl, auto_renewal=auto_renewal
        )
