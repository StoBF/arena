"""Utility functions for WebSocket handlers.

This module encapsulates the common subscribe/publish loop used by chat
endpoints.  Handlers pass a Redis channel name and a callback to persist
incoming messages; the helper deals with task lifecycle and cancellation.
"""
import asyncio
import json
from fastapi import WebSocket, WebSocketDisconnect
from app.core.redis_pubsub import publish_message, subscribe_channel


async def websocket_loop(websocket: WebSocket, channel: str, save_callback):
    """Generic websocket loop.

    * `channel` is the redis pub/sub channel to which this socket is
      subscribed.
    * `save_callback` is a coroutine that accepts a single argument (the raw
      text received) and persists it (usually inserting a ChatMessage row).
    """
    send_task = None
    try:
        async def sender():
            async for msg in subscribe_channel(channel):
                await websocket.send_text(json.dumps(msg))
        send_task = asyncio.create_task(sender())
        while True:
            data = await websocket.receive_text()
            await save_callback(data)
            await publish_message(channel, data)
    except WebSocketDisconnect:
        if send_task:
            send_task.cancel()
