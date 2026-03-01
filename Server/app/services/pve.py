from app.database.models.pve import MobTemplate, RaidArenaInstance
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime
from typing import List
import random

class PvEService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def generate_raid_arena_instance(self, user_id: int, hero_levels: List[int]) -> RaidArenaInstance:
        # Визначаємо середній рівень команди
        avg_level = int(sum(hero_levels) / max(1, len(hero_levels)))
        # Вибираємо мобів, які підходять під рівень
        mobs_query = await self.session.execute(
            MobTemplate.__table__.select().where(MobTemplate.level <= avg_level + 2)
        )
        all_mobs = mobs_query.fetchall()
        # Вибираємо 3 випадкових моби для хвилі
        mob_ids = [row.id for row in random.sample(all_mobs, min(3, len(all_mobs)))] if all_mobs else []
        raid_instance = RaidArenaInstance(
            user_id=user_id,
            created_at=datetime.utcnow(),
            wave=1,
            mobs=mob_ids,
            boss_id=None,
            is_active=True
        )
        self.session.add(raid_instance)
        await self.session.flush()
        return raid_instance 