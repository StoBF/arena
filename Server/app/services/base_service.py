from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException
from sqlalchemy.exc import SQLAlchemyError
from app.schemas.user import UserOut
from typing import List

class BaseService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def commit_or_rollback(self):
        try:
            await self.session.commit()
        except SQLAlchemyError:
            await self.session.rollback()
            raise HTTPException(500, "Database error")

    async def return_user(self, user):
        return UserOut.from_orm(user)

    async def place_bid(self, hero_id, user_id, amount):
        async with self.session.begin():
            hero = await self.session.get(Hero, hero_id, with_for_update=True)
            # перевірка owner_id, балансу, запис bid 