"""
Raid service — v2

Uses hero_generation_level for difficulty scaling.
Mob templates still have a ``level`` column for difficulty banding.
No hero perks; mob perks are dropped from wave data (not used in combat).
"""
from __future__ import annotations

import random as _random
from datetime import datetime
from random import random
from typing import Any, Dict, List

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database.models.hero import Hero
from app.database.models.pve import MobTemplate, PvEBattleLog, RaidArenaInstance
from app.database.models.raid_boss import RaidBoss
from app.services.actions import resolve_action
from app.services.inventory import StashService

# ── Inline defaults (no dependency on settings for these) ─────────
_RAID_WAVE_COUNT: int = 3
_RAID_MIN_ENEMIES: int = 2
_RAID_MAX_ENEMIES: int = 4
_RAID_COMPLETED_STATUS: str = "completed"


class RaidService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ── instance creation ────────────────────────────────────────
    async def start_instance(
        self,
        boss_id: int,
        user_id: int,
        hero_ids: List[int],
    ) -> RaidArenaInstance:
        """Create a raid arena for the given boss and heroes."""

        # 1. Validate ownership
        result = await self.db.execute(
            select(Hero)
            .where(Hero.id.in_(hero_ids), Hero.owner_id == user_id)
        )
        heroes: List[Hero] = list(result.scalars().all())
        if len(heroes) != len(hero_ids):
            raise ValueError("Invalid hero selection or ownership")

        # 2. Average generation level (replaces v1 avg_level)
        avg_gen = sum(
            (h.hero_generation_level or 1) for h in heroes
        ) // max(1, len(heroes))

        # 3. Create instance
        now = datetime.utcnow()
        inst = RaidArenaInstance(
            user_id=user_id,
            team_ids=hero_ids,
            boss_id=boss_id,
            waves=[],
            current_wave=1,
            status="active",
            created_at=now,
            is_active=True,
        )
        self.db.add(inst)
        await self.db.flush()

        # 4. Generate waves & persist
        await self._generate_waves(inst.id, avg_gen)
        return inst

    # ── wave generation ──────────────────────────────────────────
    async def _generate_waves(
        self,
        instance_id: int,
        avg_gen: int,
    ) -> List[List[Dict[str, Any]]]:
        """Generate N waves by sampling non-boss mob templates."""

        result = await self.db.execute(
            select(MobTemplate).where(MobTemplate.is_boss == False)  # noqa: E712
        )
        templates: List[MobTemplate] = list(result.scalars().all())

        waves: List[List[Dict[str, Any]]] = []
        for _ in range(_RAID_WAVE_COUNT):
            cnt = _random.randint(_RAID_MIN_ENEMIES, _RAID_MAX_ENEMIES)
            group = _random.sample(templates, min(cnt, len(templates)))

            wave_data: List[Dict[str, Any]] = []
            for mob in group:
                # Scale mob difficulty around party generation level
                mob_gen = max(1, avg_gen + _random.randint(-2, 1))
                wave_data.append({
                    "template_id": mob.id,
                    "level": mob_gen,
                    "stats": mob.base_stats or {},
                })
            waves.append(wave_data)

        # Persist back
        inst = await self.db.get(RaidArenaInstance, instance_id)
        inst.waves = waves  # type: ignore[assignment]
        await self.db.commit()
        await self.db.refresh(inst)
        return waves

    # ── team-defeated check ──────────────────────────────────────
    async def is_team_defeated(self, instance_id: int) -> bool:
        inst = await self.db.get(RaidArenaInstance, instance_id)
        result = await self.db.execute(
            select(Hero).where(Hero.id.in_(inst.team_ids))
        )
        heroes = list(result.scalars().all())
        return all(h.is_dead for h in heroes)

    # ── battle execution ─────────────────────────────────────────
    async def run_pve_battle(self, instance_id: int) -> PvEBattleLog:
        """Execute all waves + boss for a PvE raid instance."""

        inst = await self.db.get(RaidArenaInstance, instance_id)
        result = await self.db.execute(
            select(Hero).where(Hero.id.in_(inst.team_ids))
        )
        heroes = list(result.scalars().all())

        events: List[Dict[str, Any]] = []

        # Iterate waves
        for idx, wave in enumerate(inst.waves, start=1):
            for enemy in wave:
                ev = await resolve_action(self.db, enemy, heroes, idx)
                events.append(ev)
            if await self.is_team_defeated(instance_id):
                break

        # Boss turn if heroes survived
        if not await self.is_team_defeated(instance_id):
            boss = await self.db.get(RaidBoss, inst.boss_id)
            if boss is not None:
                boss_entity = {
                    "id": boss.id,
                    "stats": {"health": 500, "stamina": 200, "defense": 40},
                }
                ev = await resolve_action(self.db, boss_entity, heroes, "boss")
                events.append(ev)

        # Outcome
        outcome = "loss" if await self.is_team_defeated(instance_id) else "win"

        log = PvEBattleLog(
            instance_id=instance_id,
            events=events,
            outcome=outcome,
            created_at=datetime.utcnow(),
        )
        self.db.add(log)

        inst.status = _RAID_COMPLETED_STATUS
        if outcome == "win":
            inst.current_wave += 1

        await self.db.commit()
        return log

    # ── reward distribution ──────────────────────────────────────
    async def drop_rewards(self, instance_id: int) -> List[Dict[str, Any]]:
        """Roll and persist loot for a completed raid instance."""

        result = await self.db.execute(
            select(PvEBattleLog)
            .where(PvEBattleLog.instance_id == instance_id)
            .order_by(PvEBattleLog.id.desc())
            .limit(1)
        )
        record = result.scalars().first()
        if not record or record.outcome != "win":
            return []

        inst = await self.db.get(RaidArenaInstance, instance_id)
        boss = await self.db.get(RaidBoss, inst.boss_id)  # type: ignore[arg-type]
        if boss is None:
            return []

        rewards: List[Dict[str, Any]] = []

        # Roll raw item drops (loot_table relationship)
        for drop in await self.db.execute(
            select(RaidBoss)
            .where(RaidBoss.id == boss.id)
            .options(selectinload(RaidBoss.loot_table))
        ):
            boss_loaded = drop.scalars().first()
            break
        else:
            boss_loaded = None

        if boss_loaded:
            for d in boss_loaded.loot_table:
                if random() < d.chance:
                    rewards.append({
                        "type": "resource",
                        "id": d.item_id,
                        "qty": 1,
                    })
            for rd in boss_loaded.drop_recipes:
                if random() < rd.chance:
                    rewards.append({"type": "recipe", "id": rd.recipe_id})

        # Persist to stash
        stash_service = StashService(self.db)
        for r in rewards:
            await stash_service.add_to_stash(inst.user_id, r["id"], r.get("qty", 1))
        await self.db.commit()
        return rewards