# app/core/redis_cache.py

import os
import json
from typing import Any, Optional
from redis.asyncio import Redis

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
        # Redis stub: no-op
        return

# Створюємо єдиний екземпляр для імпорту в інших модулях
redis_cache = RedisCache()
