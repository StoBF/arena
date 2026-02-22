from sqlalchemy.future import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.database.models.models import Item
from app.services.base_service import BaseService

class ItemService(BaseService):
    async def create_item(self, name: str, description: str, bonus_strength: int, bonus_agility: int, bonus_intelligence: int):
        item = Item(name=name, description=description, bonus_strength=bonus_strength, bonus_agility=bonus_agility, bonus_intelligence=bonus_intelligence)
        self.session.add(item)
        await self.commit_or_rollback()
        await self.session.refresh(item)
        return item

    async def get_item(self, item_id: int):
        result = await self.session.execute(select(Item).where(Item.id == item_id))
        return result.scalars().first()

    async def list_items(self):
        result = await self.session.execute(select(Item))
        return result.scalars().all()

    async def update_item(self, item_id: int, **kwargs):
        item = await self.get_item(item_id)
        if item:
            for key, val in kwargs.items():
                setattr(item, key, val)
            await self.commit_or_rollback()
            await self.session.refresh(item)
        return item

    async def delete_item(self, item_id: int):
        item = await self.get_item(item_id)
        if item:
            await self.session.delete(item)
            await self.commit_or_rollback()
        return item