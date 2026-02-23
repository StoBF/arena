from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database.models.models import Announcement
from app.services.base_service import BaseService

class AnnouncementService(BaseService):
    async def create_announcement(self, message: str, author_id: int = None):
        ann = Announcement(message=message, author_id=author_id)
        self.session.add(ann)
        await self.session.flush()
        await self.session.refresh(ann)
        return ann

    async def get_announcement(self, announcement_id: int):
        result = await self.session.execute(select(Announcement).where(Announcement.id == announcement_id))
        return result.scalars().first()

    async def list_announcements(self, limit: int = 50):
        result = await self.session.execute(
            select(Announcement).order_by(Announcement.created_at.desc()).limit(limit)
        )
        return result.scalars().all()

    async def delete_announcement(self, announcement_id: int):
        ann = await self.get_announcement(announcement_id)
        if ann:
            await self.session.delete(ann)
            await self.commit_or_rollback()
        return ann