"""
ClanService — business logic for the clan system.

Covers:
  create / update / delete clan
  member management (join, leave, kick, role, nickname, permissions)
  application lifecycle (apply, accept, reject, interview, trial)
  storage (deposit, withdraw, reserve, release)
  trust system (add_trust_points, compute_level)
  meetup + QR (create, generate_qr, check_in, close)
  activity log helper
"""
from __future__ import annotations

import hashlib
import random
import re
import string
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional

from fastapi import HTTPException
from sqlalchemy import func, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database.models.clan import (
    Clan, ClanApplication, ClanActivityLog, ClanMember,
    ClanMeetup, ClanMeetupParticipant,
    ClanStorageItem, ClanStorageTransaction,
    ApplicationStatus, ClanRole, MeetupStatus, StorageAction,
)

# ── Trust-level thresholds ────────────────────────────────────────────────────
TRUST_THRESHOLDS = [0, 50, 150, 350, 700, 1200, 2000, 3000, 5000, 8000]

# ── Clan XP per action ────────────────────────────────────────────────────────
CLAN_XP = {
    "member_joined":     10,
    "storage_deposit":    5,
    "meetup_checkin":    30,
    "clan_battle_win":   50,
    "clan_battle_loss":  15,
    "event_completed":   40,
}
CLAN_LEVEL_XP = [0, 200, 600, 1400, 3000, 5500, 9000, 14000, 21000, 30000]

# ── QR TTL ───────────────────────────────────────────────────────────────────
QR_TTL_MINUTES = 15


def _slugify(name: str) -> str:
    s = name.lower().strip()
    s = re.sub(r"[^a-z0-9\-_]", "-", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    return s[:80]


def _trust_level(points: int) -> int:
    for lvl in range(len(TRUST_THRESHOLDS) - 1, -1, -1):
        if points >= TRUST_THRESHOLDS[lvl]:
            return lvl
    return 0


def _clan_level(xp: int) -> int:
    for lvl in range(len(CLAN_LEVEL_XP) - 1, -1, -1):
        if xp >= CLAN_LEVEL_XP[lvl]:
            return min(lvl + 1, 10)
    return 1


class ClanService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Log helper ────────────────────────────────────────────────────────────
    async def _log(self, clan_id: int, actor_id: Optional[int],
                   action: str, payload: Dict[str, Any] = {}):
        self.db.add(ClanActivityLog(
            clan_id=clan_id, actor_user_id=actor_id,
            action_type=action, payload_json=payload,
        ))

    # ── Clan CRUD ─────────────────────────────────────────────────────────────
    async def create_clan(self, owner_id: int, data: Dict[str, Any]) -> Clan:
        # One clan at a time
        existing = await self.db.execute(
            select(ClanMember).where(ClanMember.user_id == owner_id)
        )
        if existing.scalars().first():
            raise HTTPException(400, "You are already a member of a clan")

        slug = _slugify(data["name"])
        # Ensure unique slug
        res = await self.db.execute(select(Clan).where(Clan.slug == slug))
        if res.scalars().first():
            slug = slug + "-" + str(random.randint(100, 999))

        clan = Clan(
            name=data["name"],
            slug=slug,
            description=data.get("description", ""),
            country_code=data.get("country_code", ""),
            region_name=data.get("region_name", ""),
            city_name=data.get("city_name", ""),
            district_name=data.get("district_name", ""),
            language=data.get("language", "en"),
            clan_type=data.get("clan_type", "local"),
            clan_mode=data.get("clan_mode", "mixed"),
            offline_friendly=data.get("offline_friendly", False),
            recruitment_mode=data.get("recruitment_mode", "by_application"),
            owner_id=owner_id,
        )
        self.db.add(clan)
        await self.db.flush()

        # Make creator the leader
        member = ClanMember(
            clan_id=clan.id,
            user_id=owner_id,
            role=ClanRole.leader,
            trust_level=9,
            trust_points=TRUST_THRESHOLDS[9],
            can_manage_members=True,
            can_manage_storage=True,
            can_withdraw_storage=True,
            can_craft_storage=True,
            can_manage_chat=True,
            can_manage_events=True,
            can_manage_recruitment=True,
        )
        self.db.add(member)
        await self._log(clan.id, owner_id, "clan_created", {"name": clan.name})
        await self.db.commit()
        await self.db.refresh(clan)
        return clan

    async def get_clan(self, clan_id: int) -> Clan:
        res = await self.db.execute(
            select(Clan)
            .where(Clan.id == clan_id, Clan.disbanded_at.is_(None))
            .options(selectinload(Clan.members))
        )
        clan = res.scalars().first()
        if not clan:
            raise HTTPException(404, "Clan not found")
        return clan

    async def search_clans(self, params: Dict[str, Any]) -> List[Clan]:
        stmt = select(Clan).where(Clan.disbanded_at.is_(None))
        for field in ("country_code", "region_name", "city_name", "clan_type",
                      "clan_mode", "recruitment_mode"):
            if params.get(field):
                stmt = stmt.where(getattr(Clan, field) == params[field])
        if params.get("offline_friendly") is not None:
            stmt = stmt.where(Clan.offline_friendly == params["offline_friendly"])
        if params.get("min_level"):
            stmt = stmt.where(Clan.level >= params["min_level"])
        if params.get("max_level"):
            stmt = stmt.where(Clan.level <= params["max_level"])
        stmt = stmt.order_by(Clan.level.desc()).limit(params.get("limit", 20))\
                   .offset(params.get("offset", 0))
        res = await self.db.execute(stmt)
        return list(res.scalars().all())

    async def update_clan(self, clan_id: int, user_id: int,
                           data: Dict[str, Any]) -> Clan:
        await self._require_role(clan_id, user_id,
                                  [ClanRole.leader, ClanRole.co_leader])
        clan = await self.get_clan(clan_id)
        for k, v in data.items():
            if v is not None and hasattr(clan, k):
                setattr(clan, k, v)
        await self.db.commit()
        return clan

    async def disband_clan(self, clan_id: int, user_id: int):
        await self._require_role(clan_id, user_id, [ClanRole.leader])
        clan = await self.db.get(Clan, clan_id)
        clan.disbanded_at = datetime.utcnow()
        await self.db.commit()

    # ── Member management ─────────────────────────────────────────────────────
    async def get_members(self, clan_id: int) -> List[ClanMember]:
        res = await self.db.execute(
            select(ClanMember).where(ClanMember.clan_id == clan_id)
        )
        return list(res.scalars().all())

    async def kick_member(self, clan_id: int, actor_id: int, target_user_id: int):
        await self._require_role(clan_id, actor_id,
                                  [ClanRole.leader, ClanRole.co_leader, ClanRole.officer])
        member = await self._get_member(clan_id, target_user_id)
        # Can't kick leader
        if member.role == ClanRole.leader:
            raise HTTPException(400, "Cannot kick the clan leader")
        await self.db.delete(member)
        await self._log(clan_id, actor_id, "member_kicked",
                         {"target": target_user_id})
        await self.db.commit()

    async def leave_clan(self, clan_id: int, user_id: int):
        member = await self._get_member(clan_id, user_id)
        if member.role == ClanRole.leader:
            raise HTTPException(400,
                "Transfer leadership before leaving")
        await self.db.delete(member)
        await self._log(clan_id, user_id, "member_left", {})
        await self.db.commit()

    async def update_role(self, clan_id: int, actor_id: int,
                           target_user_id: int, new_role: str):
        await self._require_role(clan_id, actor_id, [ClanRole.leader, ClanRole.co_leader])
        member = await self._get_member(clan_id, target_user_id)
        member.role = new_role
        await self._log(clan_id, actor_id, "role_changed",
                         {"target": target_user_id, "role": new_role})
        await self.db.commit()

    async def update_nickname(self, clan_id: int, actor_id: int,
                               target_user_id: int, nickname: str):
        # Member can set own; officer+ can set any
        if actor_id != target_user_id:
            await self._require_role(clan_id, actor_id,
                                      [ClanRole.leader, ClanRole.co_leader, ClanRole.officer])
        member = await self._get_member(clan_id, target_user_id)
        member.nickname = nickname
        await self.db.commit()

    async def update_permissions(self, clan_id: int, actor_id: int,
                                  target_user_id: int, perms: Dict[str, Any]):
        await self._require_role(clan_id, actor_id, [ClanRole.leader, ClanRole.co_leader])
        member = await self._get_member(clan_id, target_user_id)
        for k, v in perms.items():
            if v is not None and hasattr(member, k):
                setattr(member, k, v)
        await self.db.commit()

    async def transfer_leadership(self, clan_id: int, current_leader_id: int,
                                   new_leader_id: int):
        await self._require_role(clan_id, current_leader_id, [ClanRole.leader])
        old = await self._get_member(clan_id, current_leader_id)
        new = await self._get_member(clan_id, new_leader_id)
        old.role = ClanRole.co_leader
        new.role = ClanRole.leader
        clan = await self.db.get(Clan, clan_id)
        clan.owner_id = new_leader_id
        await self._log(clan_id, current_leader_id, "leadership_transferred",
                         {"to": new_leader_id})
        await self.db.commit()

    # ── Applications ──────────────────────────────────────────────────────────
    async def apply(self, clan_id: int, user_id: int,
                     data: Dict[str, Any]) -> ClanApplication:
        # Already a member?
        existing_m = await self.db.execute(
            select(ClanMember).where(ClanMember.user_id == user_id)
        )
        if existing_m.scalars().first():
            raise HTTPException(400, "Already a clan member")

        app = ClanApplication(
            clan_id=clan_id, user_id=user_id,
            message=data.get("message", ""),
            city_name=data.get("city_name", ""),
            playstyle=data.get("playstyle", ""),
            availability_text=data.get("availability_text", ""),
        )
        self.db.add(app)
        await self.db.commit()
        await self.db.refresh(app)
        return app

    async def list_applications(self, clan_id: int, user_id: int,
                                  status: Optional[str] = None) -> List[ClanApplication]:
        await self._require_role(clan_id, user_id,
                                  [ClanRole.leader, ClanRole.co_leader,
                                   ClanRole.officer, ClanRole.recruiter])
        stmt = select(ClanApplication).where(ClanApplication.clan_id == clan_id)
        if status:
            stmt = stmt.where(ClanApplication.status == status)
        res = await self.db.execute(stmt)
        return list(res.scalars().all())

    async def _update_application(self, app_id: int, reviewer_id: int,
                                   new_status: str, note: str = ""):
        res = await self.db.execute(
            select(ClanApplication).where(ClanApplication.id == app_id)
        )
        app = res.scalars().first()
        if not app:
            raise HTTPException(404, "Application not found")
        await self._require_role(app.clan_id, reviewer_id,
                                  [ClanRole.leader, ClanRole.co_leader,
                                   ClanRole.officer, ClanRole.recruiter])
        app.status = new_status
        app.reviewed_by = reviewer_id
        app.reviewed_at = datetime.utcnow()
        app.decision_note = note
        return app

    async def accept_application(self, app_id: int, reviewer_id: int,
                                  note: str = "") -> ClanApplication:
        app = await self._update_application(app_id, reviewer_id,
                                              ApplicationStatus.accepted, note)
        # Add as trial member
        member = ClanMember(
            clan_id=app.clan_id, user_id=app.user_id, role=ClanRole.trial
        )
        self.db.add(member)
        await self._log(app.clan_id, reviewer_id, "application_accepted",
                         {"applicant": app.user_id})
        await self._add_clan_xp(app.clan_id, "member_joined")
        await self.db.commit()
        return app

    async def reject_application(self, app_id: int, reviewer_id: int,
                                   note: str = "") -> ClanApplication:
        app = await self._update_application(app_id, reviewer_id,
                                              ApplicationStatus.rejected, note)
        await self.db.commit()
        return app

    async def set_interview_status(self, app_id: int, reviewer_id: int,
                                    status: str, note: str = ""):
        app = await self._update_application(app_id, reviewer_id, status, note)
        await self.db.commit()
        return app

    # ── Storage ───────────────────────────────────────────────────────────────
    async def get_storage(self, clan_id: int) -> List[ClanStorageItem]:
        res = await self.db.execute(
            select(ClanStorageItem).where(ClanStorageItem.clan_id == clan_id)
        )
        return list(res.scalars().all())

    async def deposit(self, clan_id: int, user_id: int,
                       item_type: str, item_id: int, qty: int, note: str = ""):
        member = await self._get_member(clan_id, user_id)
        stmt = (
            pg_insert(ClanStorageItem)
            .values(clan_id=clan_id, item_type=item_type,
                    item_id=item_id, quantity=qty, reserved_quantity=0)
            .on_conflict_do_update(
                index_elements=["clan_id", "item_type", "item_id"],
                set_={"quantity": ClanStorageItem.quantity + qty}
            )
        )
        await self.db.execute(stmt)
        self._add_tx(clan_id, user_id, StorageAction.deposit, item_type, item_id, qty, note)
        await self._add_trust(clan_id, user_id, qty * 2)
        await self._add_clan_xp(clan_id, "storage_deposit")
        await self.db.commit()

    async def withdraw(self, clan_id: int, user_id: int,
                        item_type: str, item_id: int, qty: int, note: str = ""):
        member = await self._get_member(clan_id, user_id)
        if not (member.can_withdraw_storage or member.role in
                (ClanRole.leader, ClanRole.co_leader, ClanRole.quartermaster)):
            raise HTTPException(403, "No permission to withdraw from storage")
        row = await self._get_storage_row(clan_id, item_type, item_id)
        available = row.quantity - row.reserved_quantity
        if available < qty:
            raise HTTPException(400, f"Only {available} units available")
        row.quantity -= qty
        self._add_tx(clan_id, user_id, StorageAction.withdraw, item_type, item_id, qty, note)
        await self.db.commit()

    async def reserve(self, clan_id: int, user_id: int,
                       item_type: str, item_id: int, qty: int, note: str = ""):
        member = await self._get_member(clan_id, user_id)
        if not (member.can_manage_storage or member.role in
                (ClanRole.leader, ClanRole.co_leader, ClanRole.quartermaster)):
            raise HTTPException(403, "No permission to reserve storage")
        row = await self._get_storage_row(clan_id, item_type, item_id)
        if row.quantity - row.reserved_quantity < qty:
            raise HTTPException(400, "Insufficient unreserved quantity")
        row.reserved_quantity += qty
        self._add_tx(clan_id, user_id, StorageAction.reserve, item_type, item_id, qty, note)
        await self.db.commit()

    async def get_storage_log(self, clan_id: int,
                               limit: int = 50) -> List[ClanStorageTransaction]:
        res = await self.db.execute(
            select(ClanStorageTransaction)
            .where(ClanStorageTransaction.clan_id == clan_id)
            .order_by(ClanStorageTransaction.created_at.desc())
            .limit(limit)
        )
        return list(res.scalars().all())

    def _add_tx(self, clan_id: int, user_id: int, action: StorageAction,
                item_type: str, item_id: int, qty: int, note: str):
        self.db.add(ClanStorageTransaction(
            clan_id=clan_id, actor_user_id=user_id,
            action_type=action, item_type=item_type,
            item_id=item_id, quantity=qty, note=note,
        ))

    async def _get_storage_row(self, clan_id: int, item_type: str,
                                item_id: int) -> ClanStorageItem:
        res = await self.db.execute(
            select(ClanStorageItem).where(
                ClanStorageItem.clan_id == clan_id,
                ClanStorageItem.item_type == item_type,
                ClanStorageItem.item_id == item_id,
            )
        )
        row = res.scalars().first()
        if not row:
            raise HTTPException(404, "Item not in clan storage")
        return row

    # ── Trust ─────────────────────────────────────────────────────────────────
    async def _add_trust(self, clan_id: int, user_id: int, points: int):
        try:
            member = await self._get_member(clan_id, user_id)
            member.trust_points += points
            member.trust_level = _trust_level(member.trust_points)
        except HTTPException:
            pass   # member left or not found — ignore

    # ── Clan XP / level ───────────────────────────────────────────────────────
    async def _add_clan_xp(self, clan_id: int, action: str):
        xp_gain = CLAN_XP.get(action, 0)
        if not xp_gain:
            return
        clan = await self.db.get(Clan, clan_id)
        if clan:
            clan.experience += xp_gain
            clan.level = _clan_level(clan.experience)

    # ── Meetup + QR ──────────────────────────────────────────────────────────
    async def create_meetup(self, clan_id: int, user_id: int,
                             data: Dict[str, Any]) -> ClanMeetup:
        member = await self._get_member(clan_id, user_id)
        if not (member.can_manage_events or
                member.role in (ClanRole.leader, ClanRole.co_leader, ClanRole.officer)):
            raise HTTPException(403, "No permission to create events")
        meetup = ClanMeetup(
            clan_id=clan_id, created_by=user_id,
            title=data["title"], description=data.get("description", ""),
            city_name=data.get("city_name", ""),
            scheduled_at=data.get("scheduled_at"),
        )
        self.db.add(meetup)
        await self.db.commit()
        await self.db.refresh(meetup)
        return meetup

    async def generate_qr(self, meetup_id: int, user_id: int) -> Dict[str, Any]:
        meetup = await self.db.get(ClanMeetup, meetup_id)
        if not meetup:
            raise HTTPException(404, "Meetup not found")
        await self._require_role(meetup.clan_id, user_id,
                                  [ClanRole.leader, ClanRole.co_leader, ClanRole.officer])
        secret = "".join(random.choices(string.ascii_letters + string.digits, k=32))
        expires = datetime.utcnow() + timedelta(minutes=QR_TTL_MINUTES)
        meetup.qr_secret  = secret
        meetup.qr_expires_at = expires
        meetup.status = MeetupStatus.active
        await self.db.commit()
        return {"qr_token": secret, "expires_at": expires.isoformat()}

    async def check_in(self, meetup_id: int, user_id: int, qr_token: str):
        meetup = await self.db.get(ClanMeetup, meetup_id)
        if not meetup or meetup.status != MeetupStatus.active:
            raise HTTPException(400, "Meetup not active")
        if not meetup.qr_secret or meetup.qr_secret != qr_token:
            raise HTTPException(400, "Invalid QR token")
        if meetup.qr_expires_at and datetime.utcnow() > meetup.qr_expires_at:
            raise HTTPException(400, "QR token expired")
        # Verify membership
        await self._get_member(meetup.clan_id, user_id)
        # Idempotent insert
        stmt = (
            pg_insert(ClanMeetupParticipant)
            .values(meetup_id=meetup_id, user_id=user_id)
            .on_conflict_do_nothing(index_elements=["meetup_id", "user_id"])
        )
        await self.db.execute(stmt)
        await self._add_trust(meetup.clan_id, user_id, 50)
        await self._add_clan_xp(meetup.clan_id, "meetup_checkin")
        await self._log(meetup.clan_id, user_id, "meetup_checkin",
                         {"meetup_id": meetup_id})
        await self.db.commit()
        return {"ok": True}

    async def close_meetup(self, meetup_id: int, user_id: int):
        meetup = await self.db.get(ClanMeetup, meetup_id)
        if not meetup:
            raise HTTPException(404, "Meetup not found")
        await self._require_role(meetup.clan_id, user_id,
                                  [ClanRole.leader, ClanRole.co_leader, ClanRole.officer])
        meetup.status = MeetupStatus.closed
        meetup.qr_secret = None
        await self.db.commit()

    async def list_meetups(self, clan_id: int) -> List[ClanMeetup]:
        res = await self.db.execute(
            select(ClanMeetup)
            .where(ClanMeetup.clan_id == clan_id)
            .options(selectinload(ClanMeetup.participants))
            .order_by(ClanMeetup.created_at.desc())
        )
        return list(res.scalars().all())

    # ── Activity log ─────────────────────────────────────────────────────────
    async def get_activity_log(self, clan_id: int,
                                limit: int = 50) -> List[ClanActivityLog]:
        res = await self.db.execute(
            select(ClanActivityLog)
            .where(ClanActivityLog.clan_id == clan_id)
            .order_by(ClanActivityLog.created_at.desc())
            .limit(limit)
        )
        return list(res.scalars().all())

    # ── Helpers ───────────────────────────────────────────────────────────────
    async def _get_member(self, clan_id: int, user_id: int) -> ClanMember:
        res = await self.db.execute(
            select(ClanMember).where(
                ClanMember.clan_id == clan_id,
                ClanMember.user_id == user_id,
            )
        )
        member = res.scalars().first()
        if not member:
            raise HTTPException(403, "Not a member of this clan")
        return member

    async def _require_role(self, clan_id: int, user_id: int,
                             allowed_roles: List[ClanRole]):
        member = await self._get_member(clan_id, user_id)
        if member.role not in allowed_roles:
            raise HTTPException(403, "Insufficient clan role")
