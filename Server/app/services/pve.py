"""
PvE service — v2

Uses hero_generation_level (not hero.level) for mob matching.
"""
from app.database.models.pve import MobTemplate, RaidArenaInstance
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime
from typing import List
import random


class PvEService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def generate_raid_arena_instance(
        self,
        user_id: int,
        hero_gen_levels: List[int],
    ) -> RaidArenaInstance:
        """Create a quick-start raid instance matched to hero generation levels.

        ``hero_gen_levels`` should contain the ``hero_generation_level``
        values for each hero in the party.
        """
        avg_gen = int(sum(hero_gen_levels) / max(1, len(hero_gen_levels)))

        # Select mob templates whose level is within range of party power
        result = await self.session.execute(
            select(MobTemplate).where(MobTemplate.level <= avg_gen + 2)
        )
        all_mobs = list(result.scalars().all())

        # Pick up to 3 random mobs for the wave
        mob_ids = (
            [m.id for m in random.sample(all_mobs, min(3, len(all_mobs)))]
            if all_mobs
            else []
        )

        raid_instance = RaidArenaInstance(
            user_id=user_id,
            team_ids=[],
            boss_id=None,
            waves=[mob_ids],
            current_wave=1,
            status="pending",
            created_at=datetime.utcnow(),
            is_active=True,
        )
        self.session.add(raid_instance)
        await self.session.flush()
        return raid_instance