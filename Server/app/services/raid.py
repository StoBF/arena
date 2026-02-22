from random import random
import random as _random
from datetime import datetime
from typing import List, Dict, Any
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.database.models.pve import PvEBattleLog, RaidArenaInstance, MobTemplate
from app.database.models.raid_boss import RaidBoss
from app.database.models.hero import Hero
from app.services.actions import resolve_action  # handles AI turn resolution
from app.services.inventory import StashService  # stash persistence via service

class RaidService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def start_instance(self, boss_id: int, user_id: int, hero_ids: List[int]) -> RaidArenaInstance:
        """
        Create a new raid arena for the given boss and heroes,
        generate waves, and persist the instance.
        """
        # 1. Validate ownership
        heroes_res = await self.db.execute(
            Hero.__table__.select().where(Hero.id.in_(hero_ids), Hero.owner_id == user_id)
        )
        heroes = heroes_res.scalars().all()
        if len(heroes) != len(hero_ids):
            raise ValueError("Invalid hero selection or ownership")
        # 2. Compute avg level
        avg_level = sum(h.level for h in heroes) // len(heroes)
        # 3. Create empty instance
        now = datetime.utcnow()
        inst = RaidArenaInstance(
            user_id=user_id,
            team_ids=hero_ids,
            boss_id=boss_id,
            waves=[],
            current_wave=1,
            status="active",
            created_at=now
        )
        self.db.add(inst)
        await self.db.flush()
        # 4. Generate waves & persist
        await self.generate_waves(inst.id, avg_level)
        return inst

    async def generate_waves(self, instance_id: int, avg_level: int) -> List[List[Dict[str, Any]]]:
        """
        Generate N waves by sampling non‐boss mobs, instantiating level/stats/perks.
        """
        # config‐driven counts
        wave_count = settings.RAID_WAVE_COUNT     # e.g. 3
        min_e, max_e = settings.RAID_MIN_ENEMIES, settings.RAID_MAX_ENEMIES

        # fetch all non‐boss templates
        res = await self.db.execute(
            MobTemplate.__table__.select().where(MobTemplate.is_boss == False)
        )
        templates = res.scalars().all()

        waves = []
        for _ in range(wave_count):
            cnt   = _random.randint(min_e, max_e)
            group = _random.sample(templates, min(cnt, len(templates)))

            wave_data = []
            for mob in group:
                lvl    = avg_level + _random.randint(-2, +1)
                stats  = mob.base_stats or {}
                perk_ids = [mp.perk_id for mp in mob.perks]
                perks = _random.sample(perk_ids, k=1) if perk_ids else []

                wave_data.append({
                    "template_id": mob.id,
                    "level": lvl,
                    "stats": stats,
                    "perks": perks
                })
            waves.append(wave_data)

        # persist back to the instance
        inst = await self.db.get(RaidArenaInstance, instance_id)
        inst.waves = waves
        await self.db.commit()
        await self.db.refresh(inst)
        return waves

    async def is_team_defeated(self, instance_id: int) -> bool:
        """
        Return True only if _all_ heroes are still dead (dead_until > now).
        """
        inst = await self.db.get(RaidArenaInstance, instance_id)
        now = datetime.utcnow()

        res = await self.db.execute(
            Hero.__table__.select().where(Hero.id.in_(inst.team_ids))
        )
        heroes = res.scalars().all()

        # If any hero is alive (not is_dead OR dead_until passed), team is NOT defeated
        for h in heroes:
            if not h.is_dead or not h.dead_until or h.dead_until <= now:
                return False
        return True

    async def run_pve_battle(self, instance_id: int) -> PvEBattleLog:
        """
        Execute all waves and boss turns for a PvE raid instance,
        record each action into PvEBattleLog and return the log.
        """
        # 1) Load the instance & heroes
        inst = await self.db.get(RaidArenaInstance, instance_id)
        res  = await self.db.execute(
            Hero.__table__.select().where(Hero.id.in_(inst.team_ids))
        )
        heroes = res.scalars().all()

        events: List[Dict[str,Any]] = []

        # 2) Iterate through each wave
        for idx, wave in enumerate(inst.waves, start=1):
            for enemy in wave:
                ev = await resolve_action(self.db, enemy, heroes, idx)
                events.append(ev)
            if await self.is_team_defeated(instance_id):
                break

        # 3) Boss's turn if heroes survived
        if not await self.is_team_defeated(instance_id):
            boss = await self.db.get(RaidBoss, inst.boss_id)
            ev   = await resolve_action(self.db, boss, heroes, "boss")
            events.append(ev)

        # 4) Determine outcome
        outcome = "loss" if await self.is_team_defeated(instance_id) else "win"

        # 5) Persist the log & update instance
        log = PvEBattleLog(
            instance_id=instance_id,
            events=events,
            outcome=outcome,
            created_at=datetime.utcnow()
        )
        self.db.add(log)

        inst.status = settings.RAID_INSTANCE_COMPLETED_STATUS  # e.g. "completed"
        if outcome == "win":
            inst.current_wave += 1

        await self.db.commit()
        return log

    async def drop_rewards(self, instance_id: int) -> List[Dict[str, Any]]:
        """
        Roll and persist loot & recipe drops for a completed raid instance.
        """
        last = await self.db.execute(
            PvEBattleLog.__table__
            .select()
            .where(PvEBattleLog.instance_id == instance_id)
            .order_by(PvEBattleLog.id.desc())
            .limit(1)
        )
        record = last.fetchone()
        if not record or record.outcome != "win":
            return []
        inst = await self.db.get(RaidArenaInstance, instance_id)
        boss = await self.db.get(RaidBoss, inst.boss_id)
        rewards = []
        # roll raw items
        for d in boss.loot_items:
            if random() < d.chance:
                rewards.append({"type":"resource","id":d.resource_id,"qty":d.quantity})
        # roll recipes
        for rd in boss.recipe_drops:
            if random() < rd.chance:
                rewards.append({"type":"recipe","id":rd.recipe_id})
        # persist to user stash via StashService
        stash_service = StashService(self.db)
        for r in rewards:
            await stash_service.add_to_stash(inst.user_id, r["id"], r.get("qty", 1))
        await self.db.commit()
        return rewards 