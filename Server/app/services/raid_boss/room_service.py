"""
Raid Room Service — create/join rooms, coalition management, roster locking.
"""
from __future__ import annotations

from datetime import datetime
from typing import List, Optional

from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.models.raid_v2 import (
    RaidRoom, RaidParticipant, RaidCoalition, RaidCoalitionClan,
    RaidBossSpawn, RaidBossTemplate,
    RoomStatus, SpawnStatus, CoalitionStatus,
)


class RoomService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Create room ───────────────────────────────────────────────────────────
    async def create_room(
        self,
        spawn_id:        int,
        creator_user_id: int,
        creator_clan_id: Optional[int] = None,
        loot_rule:       str = "contribution",
    ) -> RaidRoom:
        spawn = await self.db.get(RaidBossSpawn, spawn_id)
        if not spawn:
            raise ValueError("Spawn not found")
        if spawn.status != SpawnStatus.open:
            raise ValueError(f"Spawn is not open (status={spawn.status})")

        room = RaidRoom(
            spawn_id        = spawn_id,
            creator_user_id = creator_user_id,
            creator_clan_id = creator_clan_id,
            status          = RoomStatus.preparing,
            loot_rule       = loot_rule,
        )
        self.db.add(room)
        await self.db.commit()
        await self.db.refresh(room)
        return room

    # ── Join room ─────────────────────────────────────────────────────────────
    async def join_room(
        self,
        room_id:  int,
        user_id:  int,
        hero_id:  int,
        clan_id:  Optional[int] = None,
    ) -> RaidParticipant:
        room = await self._get_room(room_id)
        if room.status != RoomStatus.preparing:
            raise ValueError("Room is not accepting participants")

        # Check max heroes per template
        template = await self._get_template_for_room(room)
        current_count = await self._participant_count(room_id)
        if current_count >= template.max_heroes:
            raise ValueError(f"Room is full (max {template.max_heroes} heroes)")

        # Check clan limit if coalition exists
        if room.coalition_id and clan_id:
            coalition_clan = await self._get_coalition_clan(room.coalition_id, clan_id)
            if coalition_clan:
                clan_hero_count = await self._clan_hero_count(room_id, clan_id)
                if clan_hero_count >= coalition_clan.hero_slots:
                    raise ValueError("Clan hero slot limit reached in coalition")

        p = RaidParticipant(
            room_id  = room_id,
            user_id  = user_id,
            hero_id  = hero_id,
            clan_id  = clan_id,
        )
        self.db.add(p)
        await self.db.commit()
        await self.db.refresh(p)
        return p

    # ── Mark ready ────────────────────────────────────────────────────────────
    async def set_ready(self, room_id: int, hero_id: int, ready: bool = True) -> None:
        result = await self.db.execute(
            select(RaidParticipant).where(
                and_(RaidParticipant.room_id == room_id,
                     RaidParticipant.hero_id == hero_id)
            )
        )
        p = result.scalar_one_or_none()
        if p:
            p.is_ready = ready
            await self.db.commit()

    # ── Lock roster ───────────────────────────────────────────────────────────
    async def lock_roster(self, room_id: int) -> RaidRoom:
        room = await self._get_room(room_id)
        if room.status != RoomStatus.preparing:
            raise ValueError("Room is not in preparing state")
        room.status    = RoomStatus.locked
        room.locked_at = datetime.utcnow()
        await self.db.commit()
        await self.db.refresh(room)
        return room

    # ── Create coalition ──────────────────────────────────────────────────────
    async def create_coalition(
        self,
        spawn_id:      int,
        leader_clan_id: int,
        loot_rule:     str = "contribution",
        name:          Optional[str] = None,
    ) -> RaidCoalition:
        spawn    = await self.db.get(RaidBossSpawn, spawn_id)
        template = await self.db.get(RaidBossTemplate, spawn.template_id) if spawn else None

        if not template or template.max_clans <= 1:
            raise ValueError("This boss does not allow coalitions")

        coalition = RaidCoalition(
            spawn_id       = spawn_id,
            leader_clan_id = leader_clan_id,
            loot_rule      = loot_rule,
            name           = name or "Coalition",
            status         = CoalitionStatus.forming,
        )
        self.db.add(coalition)
        await self.db.flush()

        # Leader clan auto-joins
        self.db.add(RaidCoalitionClan(
            coalition_id = coalition.id,
            clan_id      = leader_clan_id,
            hero_slots   = template.max_heroes // template.max_clans,
            accepted     = True,
            accepted_at  = datetime.utcnow(),
        ))
        await self.db.commit()
        await self.db.refresh(coalition)
        return coalition

    # ── Invite clan to coalition ──────────────────────────────────────────────
    async def invite_clan(
        self,
        coalition_id: int,
        clan_id:      int,
        hero_slots:   Optional[int] = None,
    ) -> RaidCoalitionClan:
        coalition = await self.db.get(RaidCoalition, coalition_id)
        if not coalition or coalition.status != CoalitionStatus.forming:
            raise ValueError("Coalition not found or not forming")

        spawn    = await self.db.get(RaidBossSpawn, coalition.spawn_id)
        template = await self.db.get(RaidBossTemplate, spawn.template_id)

        # Count current clans
        result = await self.db.execute(
            select(RaidCoalitionClan).where(
                RaidCoalitionClan.coalition_id == coalition_id
            )
        )
        current_clans = list(result.scalars().all())
        if len(current_clans) >= template.max_clans:
            raise ValueError(f"Coalition is full (max {template.max_clans} clans)")

        slots = hero_slots or (template.max_heroes // template.max_clans)
        invite = RaidCoalitionClan(
            coalition_id = coalition_id,
            clan_id      = clan_id,
            hero_slots   = slots,
            accepted     = False,
        )
        self.db.add(invite)
        await self.db.commit()
        await self.db.refresh(invite)
        return invite

    # ── Accept coalition invite ───────────────────────────────────────────────
    async def accept_invite(self, coalition_id: int, clan_id: int) -> RaidCoalitionClan:
        result = await self.db.execute(
            select(RaidCoalitionClan).where(
                and_(RaidCoalitionClan.coalition_id == coalition_id,
                     RaidCoalitionClan.clan_id      == clan_id)
            )
        )
        invite = result.scalar_one_or_none()
        if not invite:
            raise ValueError("Invite not found")
        invite.accepted    = True
        invite.accepted_at = datetime.utcnow()
        await self.db.commit()
        await self.db.refresh(invite)
        return invite

    # ── Get room details ──────────────────────────────────────────────────────
    async def get_room(self, room_id: int) -> Optional[RaidRoom]:
        return await self._get_room(room_id)

    async def get_participants(self, room_id: int) -> List[RaidParticipant]:
        result = await self.db.execute(
            select(RaidParticipant).where(RaidParticipant.room_id == room_id)
        )
        return list(result.scalars().all())

    # ── Internal helpers ──────────────────────────────────────────────────────
    async def _get_room(self, room_id: int) -> RaidRoom:
        room = await self.db.get(RaidRoom, room_id)
        if not room:
            raise ValueError(f"Room {room_id} not found")
        return room

    async def _get_template_for_room(self, room: RaidRoom) -> RaidBossTemplate:
        spawn    = await self.db.get(RaidBossSpawn, room.spawn_id)
        template = await self.db.get(RaidBossTemplate, spawn.template_id)
        return template

    async def _participant_count(self, room_id: int) -> int:
        result = await self.db.execute(
            select(RaidParticipant).where(RaidParticipant.room_id == room_id)
        )
        return len(result.scalars().all())

    async def _clan_hero_count(self, room_id: int, clan_id: int) -> int:
        result = await self.db.execute(
            select(RaidParticipant).where(
                and_(RaidParticipant.room_id == room_id,
                     RaidParticipant.clan_id == clan_id)
            )
        )
        return len(result.scalars().all())

    async def _get_coalition_clan(
        self, coalition_id: int, clan_id: int
    ) -> Optional[RaidCoalitionClan]:
        result = await self.db.execute(
            select(RaidCoalitionClan).where(
                and_(RaidCoalitionClan.coalition_id == coalition_id,
                     RaidCoalitionClan.clan_id      == clan_id)
            )
        )
        return result.scalar_one_or_none()
