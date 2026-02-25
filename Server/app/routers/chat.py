from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends, HTTPException, Query, Body
from jose import jwt, JWTError
from app.auth import oauth2_scheme, get_current_user_info
from app.database.models.user import User
from app.database.session import get_session, AsyncSessionLocal
from app.utils.jwt import decode_access_token
from sqlalchemy.future import select
import json
from typing import Dict, List, Optional
from app.database.models.models import ChatMessage, OfflineMessage
from app.schemas.user import UserOut
from app.schemas.chat import ChatMessageOut
from app.core.redis_pubsub import redis_pubsub, publish_message, subscribe_channel
import asyncio
from app.services.notification import NotificationService

router = APIRouter()

# WebSocket authentication uses JWT access tokens; helper provided by utils/jwt
from app.utils.jwt import get_user_id_from_token  # replaces previous local impl
from app.routers._ws import websocket_loop

@router.websocket("/ws/general")
async def ws_general(websocket: WebSocket):
    token = websocket.query_params.get("token")
    user_id = await get_user_id_from_token(token) if token else None
    if not user_id:
        await websocket.close(code=1008)
        return
    await websocket.accept()
    # define persistence callback
    async def save(data):
        async with AsyncSessionLocal() as db:
            msg = ChatMessage(sender_id=user_id, text=data, channel="general")
            db.add(msg)
            await db.commit()
    await websocket_loop(websocket, "general", save)

@router.websocket("/ws/trade")
async def ws_trade(websocket: WebSocket):
    token = websocket.query_params.get("token")
    user_id = await get_user_id_from_token(token) if token else None
    if not user_id:
        await websocket.close(code=1008)
        return
    await websocket.accept()
    async def save(data):
        async with AsyncSessionLocal() as db:
            msg = ChatMessage(sender_id=user_id, text=data, channel="trade")
            db.add(msg)
            await db.commit()
    await websocket_loop(websocket, "trade", save)

@router.websocket("/ws/private")
async def ws_private(websocket: WebSocket):
    token = websocket.query_params.get("token")
    user_id = await get_user_id_from_token(token) if token else None
    if not user_id:
        await websocket.close(code=1008)
        return
    # Додаємо користувача до онлайн-сету
    await redis_pubsub.sadd("online_users", user_id)
    await websocket.accept()
    # Доставляємо офлайн-повідомлення при підключенні
    async with AsyncSessionLocal() as db:
        await NotificationService.send_offline_messages(user_id, db)

    async def save(data):
        # data is raw string containing json with to/text
        obj = json.loads(data)
        tgt = obj.get("to")
        txt = obj.get("text")
        if tgt:
            async with AsyncSessionLocal() as db:
                msg = ChatMessage(sender_id=user_id, text=txt, channel="private", recipient_id=tgt)
                db.add(msg)
                await db.commit()
            is_online = await redis_pubsub.sismember("online_users", tgt)
            if is_online:
                await publish_message("private", {"type": "private", "from": user_id, "text": txt}, user_id=tgt)
            else:
                async with AsyncSessionLocal() as db:
                    offline = OfflineMessage(sender_id=user_id, recipient_id=tgt, text=txt)
                    db.add(offline)
                    await db.commit()
            await websocket.send_text(json.dumps({"type": "private", "to": tgt, "text": txt}))
        else:
            await websocket.send_text(json.dumps({"type": "system", "text": f"User {tgt} is offline."}))

    await websocket_loop(websocket, "private", save)

# Для системних повідомлень з інших частин коду:
def send_system_message(user_id: int, text: str):
    asyncio.create_task(publish_message("private", {"type": "system", "text": text}, user_id=user_id))

@router.get(
    "/chat/history",
    response_model=List[ChatMessageOut],
    summary="Get chat message history",
    description="Returns a list of chat messages for the specified channel (general, trade, or private). Optionally filter by user_id."
)
async def chat_history(
    channel: str = Query(..., regex="^(general|trade|private)$"),
    user_id: Optional[int] = None,
    limit: int = 50,
    db=Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    query = select(ChatMessage).where(ChatMessage.channel == channel)
    if user_id:
        query = query.where(ChatMessage.sender_id == user_id)
    query = query.order_by(ChatMessage.created_at.desc()).limit(limit)
    result = await db.execute(query)
    messages = result.scalars().all()
    return [ChatMessageOut.from_orm(m) for m in messages]

@router.delete(
    "/chat/message/{message_id}",
    response_model=ChatMessageOut,
    summary="Delete a chat message",
    description="Deletes a chat message by its ID. Only moderators or admins can delete messages."
)
async def delete_message(message_id: int, db=Depends(get_session), current_user=Depends(get_current_user_info)):
    # Перевірка ролі
    if current_user.get("role", "user") not in ("admin", "moderator"):
        raise HTTPException(403, "Only moderators or admins can delete messages")
    msg = await db.get(ChatMessage, message_id)
    if not msg:
        raise HTTPException(404, "Message not found")
    await db.delete(msg)
    await db.commit()
    return ChatMessageOut.from_orm(msg)

@router.post(
    "/chat/system-message",
    summary="Send a system message",
    description="Sends a system message to a specific user. Only admins can send system messages."
)
async def send_system_message_rest(
    to_user_id: int = Body(...),
    text: str = Body(...),
    current_user=Depends(get_current_user_info)
):
    if current_user.get("role", "user") != "admin":
        raise HTTPException(403, "Only admins can send system messages")
    send_system_message(to_user_id, text)
    return {"status": "sent"}

@router.get(
    "/chat/private-history",
    response_model=List[ChatMessageOut],
    summary="Get private chat history",
    description="Returns the private chat history between two users. Only participants, moderators, or admins can view the conversation."
)
async def private_history(
    user_id: int = Query(...),
    other_id: int = Query(...),
    limit: int = 50,
    db=Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    # Дозволяємо лише учасникам діалогу або модераторам/адмінам
    allowed = current_user.get("user_id") in (user_id, other_id) or current_user.get("role", "user") in ("admin", "moderator")
    if not allowed:
        raise HTTPException(403, "Forbidden")
    query = select(ChatMessage).where(
        ChatMessage.channel == "private",
        ((ChatMessage.sender_id == user_id) & (ChatMessage.recipient_id == other_id)) |
        ((ChatMessage.sender_id == other_id) & (ChatMessage.recipient_id == user_id))
    ).order_by(ChatMessage.created_at.desc()).limit(limit)
    result = await db.execute(query)
    messages = result.scalars().all()
    return [ChatMessageOut.from_orm(m) for m in messages] 