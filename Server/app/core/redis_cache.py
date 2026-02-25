# app/core/redis_cache.py

import os
import json
from typing import Any, Optional
from redis.asyncio import Redis
from app.core.events import subscribe

# Read Redis URL from environment; avoid hardcoded defaults
REDIS_URL = os.getenv("REDIS_URL")
if not REDIS_URL:
    # In testing environments this module may be used as a stub; do not raise here.
    REDIS_URL = None

class RedisCache:
    def __init__(self):
        self._client: Optional[Redis] = None

    async def connect(self):
        # Redis stub: do not connect in tests
        return

    async def close(self):
        if self._client:
            await self._client.close()
            self._client = None

    async def get(self, key: str) -> Any:
        # Redis stub: always return None
        return None

    async def set(self, key: str, value: Any, expire: int = 60):
        # Redis stub: no-op
        return

    async def delete(self, key: str):
        # Delete a single key or pattern.  If the client is not connected (eg.
        # during tests) this is a no-op.  Real Redis instance supports glob
        # patterns via ``KEYS`` or ``SCAN``.  We prefer ``SCAN`` for safety but
        # ``KEYS`` is simpler for a small dataset.
        if not self._client:
            return
        if "*" in key or "?" in key or "[" in key:
            # treat as pattern
            keys = await self._client.keys(key)
            if keys:
                await self._client.delete(*keys)
        else:
            await self._client.delete(key)

# Створюємо єдиний екземпляр для імпорту в інших модулях
redis_cache = RedisCache()


# subscribe to cache invalidation events so that callers do not need to
# directly import ``redis_cache``.  This keeps services decoupled and makes
# testing easier (event emitter can be drained or stubbed).
async def _invalidate_handler(key: str):
    await redis_cache.delete(key)

subscribe("cache_invalidate", _invalidate_handler)
