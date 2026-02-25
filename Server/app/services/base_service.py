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

    def _txn(self):
        """Return a transaction context manager.

        If a transaction is already active on the session we start a
        nested (savepoint) transaction so that callers can safely nest
        ``async with self._txn():`` blocks without interfering with the
        outer transaction.  This mirrors the helper previously living in
        ``EquipmentService`` and ``AuctionService``.
        """
        if self.session.in_transaction():
            return self.session.begin_nested()
        return self.session.begin()

    async def place_bid(self, hero_id, user_id, amount):
        async with self.session.begin():
            hero = await self.session.get(Hero, hero_id, with_for_update=True)
            # перевірка owner_id, балансу, запис bid 