import asyncio
import json
from redis.asyncio import Redis
from typing import AsyncGenerator, Optional
import os

REDIS_URL = os.getenv("REDIS_URL")

# In test environments the REDIS_URL may be intentionally unset; provide
# a lightweight no-op stub so import-time operations and test collection
# do not fail. In production the environment must provide `REDIS_URL`.
if REDIS_URL:
    redis_pubsub = Redis.from_url(REDIS_URL, encoding="utf-8", decode_responses=True)
else:
    class _StubPubSub:
        async def publish(self, *args, **kwargs):
            return 0

        def pubsub(self):
            return self

        async def subscribe(self, *args, **kwargs):
            return

        async def listen(self):
            if False:
                yield

        async def unsubscribe(self, *args, **kwargs):
            return

        async def close(self):
            return

    redis_pubsub = _StubPubSub()

# Канали: general, trade, private:{user_id}
def get_channel_name(channel: str, user_id: Optional[int] = None) -> str:
    if channel in ("general", "trade"):
        return f"chat:{channel}"
    elif channel == "private" and user_id is not None:
        return f"chat:private:{user_id}"
    raise ValueError("Invalid channel")

async def publish_message(channel: str, message: dict, user_id: Optional[int] = None):
    chan = get_channel_name(channel, user_id)
    await redis_pubsub.publish(chan, json.dumps(message))

async def subscribe_channel(channel: str, user_id: Optional[int] = None) -> AsyncGenerator[dict, None]:
    chan = get_channel_name(channel, user_id)
    pubsub = redis_pubsub.pubsub()
    await pubsub.subscribe(chan)
    try:
        async for msg in pubsub.listen():
            if msg["type"] == "message":
                yield json.loads(msg["data"])
    finally:
        await pubsub.unsubscribe(chan)
        await pubsub.close() 