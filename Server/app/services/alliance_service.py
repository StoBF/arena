"""
Alliance Service
==================
Alliances are persistent political unions of up to 5 clans.

Key mechanics:
  - Only clan leaders (or co-leaders) can create / join / leave alliances.
  - Founding clan becomes the leader clan.
  - Weekly upkeep is deducted from the war chest; failure to pay triggers
    a "distress" flag (no territory bonuses until paid).
  - Alliance size (number of clans) applies a diminishing-return penalty:
      1-3 clans  → 0%  penalty
      4 clans    → 5%  penalty on territory income
      5 clans    → 12% penalty on territory income
  - XP is earned through: territory control ticks, alliance wars, large raids.
  - Rank thresholds: 0=Guild (<1000 XP), 1=Order (1000–9999 XP),
      2=Empire (10000+ XP)
"""
from __future__ import annotations

from datetime import datetime
from typing import Dict, List, Optional

from sqlalchemy import select, and_, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.game_config import cfg
from app.database.models.game_systems import (
    Alliance, AllianceMember, AllianceWarChest,
    AllianceRole, AllianceStatus,
)


class AllianceService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Create ────────────────────────────────────────────────────────────────
    async def create_alliance(
        self,
        name:            str,
        tag:             str,
        description:     str,
        founding_clan_id: int,
        user_id:         int,
    ) -> Alliance:
        await self._assert_clan_leader(founding_clan_id, user_id)

        # Check clan not already in an alliance
        await self._assert_not_in_alliance(founding_clan_id)

        alliance = Alliance(
            name             = name,
            tag              = tag.upper()[:8],
            description      = description,
            founder_clan_id  = founding_clan_id,
            leader_clan_id   = founding_clan_id,
            weekly_upkeep    = cfg.alliance.upkeep_per_clan,
        )
        self.db.add(alliance)
        await self.db.flush()

        # Founding clan joins as founder
        member = AllianceMember(
            alliance_id = alliance.id,
            clan_id     = founding_clan_id,
            role        = AllianceRole.founder,
        )
        self.db.add(member)

        # War chest
        chest = AllianceWarChest(alliance_id=alliance.id)
        self.db.add(chest)

        await self.db.commit()
        await self.db.refresh(alliance)
        return alliance

    # ── Invite / join ─────────────────────────────────────────────────────────
    async def invite_clan(
        self,
        alliance_id: int,
        clan_id:     int,
        user_id:     int,   # must be alliance leader or officer
    ) -> AllianceMember:
        alliance = await self._get_alliance(alliance_id)

        # Count existing members
        count = await self._member_count(alliance_id)
        if count >= alliance.max_clans:
            raise ValueError(
                f"Alliance is full ({count}/{alliance.max_clans} clans)"
            )

        await self._assert_alliance_officer(alliance_id, user_id)
        await self._assert_not_in_alliance(clan_id)

        member = AllianceMember(
            alliance_id = alliance_id,
            clan_id     = clan_id,
            role        = AllianceRole.member,
        )
        self.db.add(member)

        # Recalculate upkeep + size penalty
        new_count = count + 1
        alliance.weekly_upkeep    = cfg.alliance.weekly_upkeep(new_count)
        alliance.size_penalty_pct = cfg.alliance.size_penalty(new_count)

        await self.db.commit()
        await self.db.refresh(member)
        return member

    # ── Leave / kick ──────────────────────────────────────────────────────────
    async def leave_alliance(
        self,
        alliance_id: int,
        clan_id:     int,
        user_id:     int,
    ) -> None:
        await self._assert_clan_leader(clan_id, user_id)

        result = await self.db.execute(
            select(AllianceMember).where(
                and_(AllianceMember.alliance_id == alliance_id,
                     AllianceMember.clan_id     == clan_id)
            )
        )
        member = result.scalar_one_or_none()
        if not member:
            raise ValueError("Clan is not in this alliance")
        if member.role == AllianceRole.founder:
            raise ValueError(
                "Founding clan cannot leave; transfer leadership first"
            )

        await self.db.delete(member)

        alliance = await self._get_alliance(alliance_id)
        new_count = max(1, await self._member_count(alliance_id))
        alliance.weekly_upkeep    = cfg.alliance.weekly_upkeep(new_count)
        alliance.size_penalty_pct = cfg.alliance.size_penalty(new_count)

        await self.db.commit()

    # ── War chest deposit ─────────────────────────────────────────────────────
    async def deposit_to_chest(
        self,
        alliance_id: int,
        clan_id:     int,
        user_id:     int,
        currency:    int,
        resources:   Optional[Dict[str, int]] = None,
    ) -> AllianceWarChest:
        await self._assert_clan_leader(clan_id, user_id)
        await self._assert_in_alliance(alliance_id, clan_id)

        chest = await self._get_chest(alliance_id)

        # Deduct from user balance
        from app.database.models.user import User
        user = await self.db.get(User, user_id)
        if float(user.balance or 0) < currency:
            raise ValueError("Insufficient balance")
        user.balance = float(user.balance) - currency

        chest.currency  += currency
        chest.updated_at = datetime.utcnow()

        if resources:
            for code, qty in resources.items():
                chest.resources[code] = chest.resources.get(code, 0) + qty

        # Track contribution
        result = await self.db.execute(
            select(AllianceMember).where(
                and_(AllianceMember.alliance_id == alliance_id,
                     AllianceMember.clan_id     == clan_id)
            )
        )
        m = result.scalar_one_or_none()
        if m:
            m.contribution += currency

        await self.db.commit()
        await self.db.refresh(chest)
        return chest

    # ── Weekly upkeep tick ────────────────────────────────────────────────────
    async def process_upkeep_tick(self, alliance_id: int) -> Dict:
        alliance = await self._get_alliance(alliance_id)
        chest    = await self._get_chest(alliance_id)

        upkeep = alliance.weekly_upkeep
        if chest.currency >= upkeep:
            chest.currency      -= upkeep
            chest.last_upkeep_at = datetime.utcnow()
            chest.updated_at     = datetime.utcnow()
            await self.db.commit()
            return {"status": "paid", "upkeep": upkeep, "balance": chest.currency}
        else:
            # Can't pay — no territory bonuses this week
            await self.db.commit()
            return {
                "status":  "defaulted",
                "upkeep":  upkeep,
                "deficit": upkeep - chest.currency,
                "note":    "Territory bonuses suspended until upkeep is paid",
            }

    # ── Add XP ────────────────────────────────────────────────────────────────
    async def add_xp(self, alliance_id: int, xp: int) -> Alliance:
        alliance    = await self._get_alliance(alliance_id)
        alliance.xp += xp
        thresholds = sorted(cfg.alliance.rank_xp_thresholds.items(), key=lambda x: x[1], reverse=True)
        for rank_name, xp_thresh in thresholds:
            if alliance.xp >= xp_thresh:
                alliance.rank = {"guild": 0, "order": 1, "empire": 2}.get(rank_name, 0)
                break
        await self.db.commit()
        await self.db.refresh(alliance)
        return alliance

    # ── Read ──────────────────────────────────────────────────────────────────
    async def get_alliance(self, alliance_id: int) -> Optional[Alliance]:
        return await self._get_alliance(alliance_id)

    async def get_alliance_for_clan(self, clan_id: int) -> Optional[Alliance]:
        result = await self.db.execute(
            select(AllianceMember).where(AllianceMember.clan_id == clan_id)
        )
        m = result.scalar_one_or_none()
        if not m:
            return None
        return await self._get_alliance(m.alliance_id)

    async def list_alliances(self, offset: int = 0, limit: int = 20) -> List[Alliance]:
        result = await self.db.execute(
            select(Alliance)
            .where(Alliance.status == AllianceStatus.active)
            .order_by(Alliance.xp.desc())
            .offset(offset)
            .limit(limit)
        )
        return list(result.scalars().all())

    async def get_members(self, alliance_id: int) -> List[AllianceMember]:
        result = await self.db.execute(
            select(AllianceMember).where(AllianceMember.alliance_id == alliance_id)
        )
        return list(result.scalars().all())

    async def get_war_chest(self, alliance_id: int) -> Optional[AllianceWarChest]:
        return await self._get_chest(alliance_id)

    async def get_summary(self, alliance_id: int) -> Dict:
        alliance = await self._get_alliance(alliance_id)
        chest    = await self._get_chest(alliance_id)
        members  = await self.get_members(alliance_id)

        rank_names = {0: "Guild", 1: "Order", 2: "Empire"}
        return {
            "id":             alliance.id,
            "name":           alliance.name,
            "tag":            alliance.tag,
            "rank":           rank_names.get(alliance.rank, "Guild"),
            "xp":             alliance.xp,
            "clan_count":     len(members),
            "max_clans":      alliance.max_clans,
            "size_penalty_pct": alliance.size_penalty_pct,
            "weekly_upkeep":  alliance.weekly_upkeep,
            "war_chest_currency": chest.currency if chest else 0,
            "war_chest_resources": chest.resources if chest else {},
            "created_at":     alliance.created_at.isoformat(),
        }

    # ── Helpers ───────────────────────────────────────────────────────────────
    async def _get_alliance(self, alliance_id: int) -> Alliance:
        a = await self.db.get(Alliance, alliance_id)
        if not a:
            raise ValueError("Alliance not found")
        return a

    async def _get_chest(self, alliance_id: int) -> AllianceWarChest:
        result = await self.db.execute(
            select(AllianceWarChest).where(
                AllianceWarChest.alliance_id == alliance_id
            )
        )
        return result.scalar_one_or_none()

    async def _member_count(self, alliance_id: int) -> int:
        result = await self.db.execute(
            select(func.count()).where(AllianceMember.alliance_id == alliance_id)
        )
        return result.scalar() or 0

    async def _assert_clan_leader(self, clan_id: int, user_id: int) -> None:
        from app.database.models.clan import ClanMember
        from sqlalchemy import or_
        result = await self.db.execute(
            select(ClanMember).where(
                and_(
                    ClanMember.clan_id == clan_id,
                    ClanMember.user_id == user_id,
                    or_(
                        ClanMember.role == "leader",
                        ClanMember.role == "co_leader",
                    ),
                )
            )
        )
        if not result.scalar_one_or_none():
            raise ValueError("Only clan leaders can perform this action")

    async def _assert_not_in_alliance(self, clan_id: int) -> None:
        result = await self.db.execute(
            select(AllianceMember).where(AllianceMember.clan_id == clan_id)
        )
        if result.scalar_one_or_none():
            raise ValueError("Clan is already in an alliance")

    async def _assert_in_alliance(self, alliance_id: int, clan_id: int) -> None:
        result = await self.db.execute(
            select(AllianceMember).where(
                and_(AllianceMember.alliance_id == alliance_id,
                     AllianceMember.clan_id     == clan_id)
            )
        )
        if not result.scalar_one_or_none():
            raise ValueError("Clan is not in this alliance")

    async def _assert_alliance_officer(self, alliance_id: int, user_id: int) -> None:
        from app.database.models.clan import ClanMember
        from sqlalchemy import or_

        # Find which clan(s) this user leads
        result = await self.db.execute(
            select(ClanMember).where(
                and_(
                    ClanMember.user_id == user_id,
                    or_(ClanMember.role == "leader", ClanMember.role == "co_leader"),
                )
            )
        )
        leader_entries = list(result.scalars().all())
        if not leader_entries:
            raise ValueError("Not a clan leader or co-leader")

        clan_ids = [e.clan_id for e in leader_entries]
        result2  = await self.db.execute(
            select(AllianceMember).where(
                and_(
                    AllianceMember.alliance_id == alliance_id,
                    AllianceMember.clan_id.in_(clan_ids),
                    AllianceMember.role.in_([
                        AllianceRole.founder,
                        AllianceRole.leader,
                        AllianceRole.officer,
                    ]),
                )
            )
        )
        if not result2.scalar_one_or_none():
            raise ValueError("Not an alliance officer")
