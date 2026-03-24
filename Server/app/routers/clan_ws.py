"""
Clan WebSocket chat.

WS /ws/clan/{clan_id}?token=...

Only verified clan members can connect.
All chat messages are persisted to clan_chat_messages.
System events are broadcast-only (not persisted).
"""
from __future__ import annotations

import json
from datetime import datetime
from typing import Dict, List

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.session import AsyncSessionLocal
from app.database.models.clan import ClanMember, ClanChatMessage

router = APIRouter(tags=["Clan Chat"])

# {clan_id: [WebSocket, ...]}
_clan_sockets: Dict[int, List[WebSocket]] = {}


async def _broadcast_clan(clan_id: int, msg: dict) -> None:
    sockets = list(_clan_sockets.get(clan_id, []))
    dead = []
    text = json.dumps(msg)
    for ws in sockets:
        try:
            await ws.send_text(text)
        except Exception:
            dead.append(ws)
    for d in dead:
        try:
            _clan_sockets[clan_id].remove(d)
        except ValueError:
            pass


async def clan_system_message(clan_id: int, action: str, payload: dict = {}) -> None:
    """Inject a system event into the clan chat channel (called from other routers)."""
    await _broadcast_clan(clan_id, {
        "type":    "system",
        "action":  action,
        "payload": payload,
        "ts":      datetime.utcnow().isoformat(),
    })


@router.websocket("/ws/clan/{clan_id}")
async def clan_chat_ws(clan_id: int, websocket: WebSocket) -> None:
    token    = websocket.query_params.get("token", "")
    user_id: int = 0

    # ── JWT + membership check ────────────────────────────────────────────
    try:
        from app.auth import decode_access_token
        payload  = decode_access_token(token)
        user_id  = int(payload.get("user_id", 0))
        async with AsyncSessionLocal() as db:
            res = await db.execute(
                select(ClanMember).where(
                    ClanMember.clan_id == clan_id,
                    ClanMember.user_id == user_id,
                )
            )
            if not res.scalars().first():
                await websocket.close(code=4003)
                return
    except Exception:
        await websocket.close(code=4001)
        return

    await websocket.accept()
    _clan_sockets.setdefault(clan_id, []).append(websocket)

    # announce join
    await _broadcast_clan(clan_id, {
        "type":    "system",
        "action":  "member_online",
        "user_id": user_id,
        "ts":      datetime.utcnow().isoformat(),
    })

    try:
        while True:
            raw  = await websocket.receive_text()
            msg  = json.loads(raw)
            text = str(msg.get("text", "")).strip()[:2000]
            if not text:
                continue

            # Persist to DB
            async with AsyncSessionLocal() as db:
                db.add(ClanChatMessage(
                    clan_id=clan_id,
                    sender_user_id=user_id,
                    message_type="chat",
                    content=text,
                ))
                await db.commit()

            await _broadcast_clan(clan_id, {
                "type":    "chat",
                "user_id": user_id,
                "text":    text,
                "ts":      datetime.utcnow().isoformat(),
            })

    except WebSocketDisconnect:
        sockets = _clan_sockets.get(clan_id, [])
        if websocket in sockets:
            sockets.remove(websocket)
        await _broadcast_clan(clan_id, {
            "type":    "system",
            "action":  "member_offline",
            "user_id": user_id,
            "ts":      datetime.utcnow().isoformat(),
        })
