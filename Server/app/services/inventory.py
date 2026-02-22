from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database.models.models import Stash
from app.services.base_service import BaseService

class StashService(BaseService):
    async def add_to_stash(self, user_id: int, item_id: int, quantity: int = 1):
        stash = (await self.session.execute(
            select(Stash).where(Stash.user_id == user_id, Stash.item_id == item_id)
        )).scalars().first()
        if stash:
            stash.quantity += quantity
        else:
            stash = Stash(user_id=user_id, item_id=item_id, quantity=quantity)
            self.session.add(stash)
        await self.commit_or_rollback()
        await self.session.refresh(stash)
        return stash

    async def get_stash_item(self, stash_id: int):
        result = await self.session.execute(select(Stash).where(Stash.id == stash_id))
        return result.scalars().first()

    async def list_stash(self, user_id: int):
        result = await self.session.execute(select(Stash).where(Stash.user_id == user_id))
        return result.scalars().all()

    async def remove_from_stash(self, user_id: int, item_id: int, quantity: int = 1):
        stash = (await self.session.execute(
            select(Stash).where(Stash.user_id == user_id, Stash.item_id == item_id)
        )).scalars().first()
        if not stash or stash.quantity < quantity:
            return False
        if stash.quantity == quantity:
            await self.session.delete(stash)
        else:
            stash.quantity -= quantity
        await self.commit_or_rollback()
        return True