import json
from sqlalchemy.future import select

class NotificationService:
    @staticmethod
    async def send_offline_messages(user_id: int, db):
        # Публікуємо всі офлайн-повідомлення у Redis Pub/Sub канал для користувача
        from app.database.models.models import OfflineMessage
        from app.core.redis_pubsub import publish_message
        result = await db.execute(
            select(OfflineMessage).where(OfflineMessage.recipient_id == user_id)
        )
        messages = result.scalars().all()
        for msg in messages:
            payload = {
                "type": "private",
                "from": msg.sender_id,
                "text": msg.text,
                "offline": True
            }
            # Публікуємо в канал 'private' для user_id
            await publish_message("private", payload, user_id)
            # Видаляємо доставлене повідомлення
            await db.delete(msg)
        await db.commit()

    @staticmethod
    async def send_system_message(user_id: int, websocket, text: str):
        await websocket.send_text(json.dumps({
            "type": "system",
            "text": text
        })) 