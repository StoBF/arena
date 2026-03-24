"""
Spawn Scheduler + Access Point Service
"""
from __future__ import annotations

from datetime import datetime, timedelta
from typing import List, Optional

from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.models.raid_v2 import (
    RaidBossTemplate, RaidBossSpawn, RaidBossProgress,
    RaidAccessScore, SpawnStatus,
)


class SpawnService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Bootstrap templates (called during seeding / startup) ────────────────
    async def ensure_templates_exist(self) -> List[RaidBossTemplate]:
        from app.services.raid_boss.catalog import BOSS_CATALOG
        from app.database.models.raid_v2 import (
            RaidBossPhase, RaidDropEntry,
            BossCategory, BossArchetype,
        )
        result = await self.db.execute(select(RaidBossTemplate))
        existing = {t.code: t for t in result.scalars().all()}

        for boss_data in BOSS_CATALOG:
            if boss_data["code"] in existing:
                continue
            t = RaidBossTemplate(
                code       = boss_data["code"],
                name       = boss_data["name"],
                category   = BossCategory(boss_data["category"]),
                archetype  = BossArchetype(boss_data["archetype"]),
                max_clans  = boss_data["max_clans"],
                max_heroes = boss_data["max_heroes"],
                num_phases = boss_data["num_phases"],
                base_level = boss_data["base_level"],
                base_hp    = boss_data["base_hp"],
                base_armor = boss_data["base_armor"],
                base_damage= boss_data["base_damage"],
                base_speed = boss_data["base_speed"],
                base_xp    = boss_data["base_xp"],
                spawn_config              = boss_data["spawn_config"],
                requires_qualification    = boss_data["requires_qualification"],
                min_access_points         = boss_data["min_access_points"],
                description               = boss_data.get("description"),
                lore                      = boss_data.get("lore"),
            )
            self.db.add(t)
            await self.db.flush()

            # Phases
            for ph in boss_data.get("phases", []):
                self.db.add(RaidBossPhase(
                    template_id    = t.id,
                    phase_number   = ph["phase_number"],
                    trigger_hp_pct = ph["trigger_hp_pct"],
                    name           = ph["name"],
                    description    = ph.get("description", ""),
                    modifiers      = ph["modifiers"],
                    abilities      = ph["abilities"],
                    arena_changes  = ph.get("arena_changes", {}),
                ))

            # Drop entries
            from app.database.models.raid_v2 import DropRarity, DropOwnership
            for dr in boss_data.get("drops", []):
                self.db.add(RaidDropEntry(
                    template_id      = t.id,
                    item_code        = dr.get("item_code"),
                    recipe_code      = dr.get("recipe_code"),
                    artifact_code    = dr.get("artifact_code"),
                    display_name     = dr["display_name"],
                    rarity           = DropRarity(dr["rarity"]),
                    ownership        = DropOwnership(dr["ownership"]),
                    drop_group       = dr.get("drop_group", "core"),
                    base_chance      = dr["base_chance"],
                    min_qty          = dr.get("min_qty", 1),
                    max_qty          = dr.get("max_qty", 1),
                    bonus_conditions = dr.get("bonus_conditions", []),
                    is_guaranteed    = dr.get("is_guaranteed", False),
                ))

            # Progress record
            self.db.add(RaidBossProgress(
                template_id = t.id,
                current_level = boss_data["base_level"],
                xp_to_next    = boss_data["base_xp"] * 5,
            ))

        await self.db.commit()
        result = await self.db.execute(select(RaidBossTemplate))
        return list(result.scalars().all())

    # ── Create scheduled spawns for all templates ────────────────────────────
    async def schedule_next_spawn(self, template: RaidBossTemplate) -> RaidBossSpawn:
        cfg = template.spawn_config
        interval_hours  = cfg.get("interval_hours", 1)
        window_minutes  = cfg.get("window_minutes", 15)

        now      = datetime.utcnow()
        opens_at = now + timedelta(seconds=5)
        closes_at = opens_at + timedelta(minutes=window_minutes)

        prog = await self._get_progress(template.id)

        spawn = RaidBossSpawn(
            template_id         = template.id,
            status              = SpawnStatus.pending,
            opens_at            = opens_at,
            closes_at           = closes_at,
            boss_level_snapshot = prog.current_level if prog else template.base_level,
            win_streak_snapshot = prog.win_streak    if prog else 0,
        )
        self.db.add(spawn)
        await self.db.commit()
        await self.db.refresh(spawn)
        return spawn

    # ── List active/open spawns ───────────────────────────────────────────────
    async def list_active_spawns(self) -> List[RaidBossSpawn]:
        now = datetime.utcnow()
        result = await self.db.execute(
            select(RaidBossSpawn)
            .where(and_(
                RaidBossSpawn.status.in_([SpawnStatus.pending, SpawnStatus.open]),
                RaidBossSpawn.closes_at >= now,
            ))
        )
        return list(result.scalars().all())

    # ── Tick: open pending spawns, expire overdue ────────────────────────────
    async def tick(self) -> None:
        now = datetime.utcnow()
        result = await self.db.execute(
            select(RaidBossSpawn).where(
                RaidBossSpawn.status.in_([SpawnStatus.pending, SpawnStatus.open])
            )
        )
        for spawn in result.scalars().all():
            if spawn.opens_at <= now and spawn.status == SpawnStatus.pending:
                spawn.status = SpawnStatus.open
            elif spawn.closes_at < now and spawn.status == SpawnStatus.open:
                spawn.status = SpawnStatus.expired
        await self.db.commit()

    async def get_spawn(self, spawn_id: int) -> Optional[RaidBossSpawn]:
        return await self.db.get(RaidBossSpawn, spawn_id)

    async def _get_progress(self, template_id: int) -> Optional[RaidBossProgress]:
        result = await self.db.execute(
            select(RaidBossProgress).where(RaidBossProgress.template_id == template_id)
        )
        return result.scalar_one_or_none()


# ── Raid Access Score Service ─────────────────────────────────────────────────

class AccessService:
    """
    Manages Raid Access Points (RAP) for clans.
    """
    def __init__(self, db: AsyncSession):
        self.db = db

    def _weekly_key(self) -> str:
        now = datetime.utcnow()
        week = now.isocalendar()[1]
        return f"weekly_{now.year}_W{week:02d}"

    def _monthly_key(self) -> str:
        now = datetime.utcnow()
        return f"monthly_{now.year}_{now.month:02d}"

    async def _get_or_create(self, clan_id: int, cycle_key: str) -> RaidAccessScore:
        result = await self.db.execute(
            select(RaidAccessScore).where(
                and_(RaidAccessScore.clan_id == cycle_key,
                     RaidAccessScore.cycle_key == cycle_key)
            )
        )
        row = result.scalar_one_or_none()
        if not row:
            row = RaidAccessScore(clan_id=clan_id, cycle_key=cycle_key, points=0)
            self.db.add(row)
            await self.db.flush()
        return row

    async def add_points(self, clan_id: int, points: int,
                         cycle: str = "weekly") -> RaidAccessScore:
        key = self._weekly_key() if cycle == "weekly" else self._monthly_key()
        row = await self._upsert(clan_id, key)
        row.points += points
        row.updated_at = datetime.utcnow()
        await self.db.commit()
        await self.db.refresh(row)
        return row

    async def _upsert(self, clan_id: int, cycle_key: str) -> RaidAccessScore:
        from sqlalchemy.dialects.postgresql import insert as pg_insert
        stmt = (
            pg_insert(RaidAccessScore)
            .values(clan_id=clan_id, cycle_key=cycle_key, points=0)
            .on_conflict_do_nothing(constraint="uq_clan_cycle")
        )
        await self.db.execute(stmt)
        result = await self.db.execute(
            select(RaidAccessScore).where(
                and_(RaidAccessScore.clan_id == clan_id,
                     RaidAccessScore.cycle_key == cycle_key)
            )
        )
        return result.scalar_one()

    async def get_ranking(self, cycle: str = "weekly", limit: int = 20) -> List[RaidAccessScore]:
        key = self._weekly_key() if cycle == "weekly" else self._monthly_key()
        result = await self.db.execute(
            select(RaidAccessScore)
            .where(RaidAccessScore.cycle_key == key)
            .order_by(RaidAccessScore.points.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    async def is_qualified(self, clan_id: int, min_points: int,
                           cycle: str = "weekly") -> bool:
        key = self._weekly_key() if cycle == "weekly" else self._monthly_key()
        result = await self.db.execute(
            select(RaidAccessScore).where(
                and_(RaidAccessScore.clan_id == clan_id,
                     RaidAccessScore.cycle_key == key)
            )
        )
        row = result.scalar_one_or_none()
        return bool(row and row.points >= min_points)

    async def get_clan_score(self, clan_id: int,
                             cycle: str = "weekly") -> Optional[RaidAccessScore]:
        key = self._weekly_key() if cycle == "weekly" else self._monthly_key()
        result = await self.db.execute(
            select(RaidAccessScore).where(
                and_(RaidAccessScore.clan_id == clan_id,
                     RaidAccessScore.cycle_key == key)
            )
        )
        return result.scalar_one_or_none()
