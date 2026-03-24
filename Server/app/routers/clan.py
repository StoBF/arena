"""
Clan router — all REST endpoints for the clan system.

Prefix: /clans
Tags:   Clans
"""
from __future__ import annotations

import hashlib
import os
import shutil
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.auth import get_current_user_info
from app.database.models.clan import (
    ClanMeetup, ClanMeetupParticipant, ClanChatMessage, RaidTicket, TicketOwnerType
)
from app.database.models.craft import CraftRecipe, CraftRecipeResource, CraftQueue, CraftedItem
from app.database.session import get_session
from app.schemas.clan import (
    ApplicationDecisionIn, ApplicationIn, ApplicationOut,
    ClanCreateIn, ClanMemberOut, ClanOut, ClanSearchParams, ClanUpdateIn,
    MeetupCreateIn, MeetupOut, NicknameUpdateIn, PermissionsUpdateIn,
    QRCheckInIn, RoleUpdateIn, StorageDepositIn, StorageItemOut,
    StorageTransactionOut, StorageWithdrawIn, TransferLeadershipIn,
    ActivityLogOut, RaidTicketOut,
)
from app.services.clan import ClanService
from sqlalchemy import select

router = APIRouter(prefix="/clans", tags=["Clans"])

EMBLEM_DIR = Path("static/clan_emblems")
EMBLEM_DIR.mkdir(parents=True, exist_ok=True)
ALLOWED_EMBLEM_EXT = {".png", ".jpg", ".jpeg", ".webp"}
MAX_EMBLEM_BYTES = 2 * 1024 * 1024   # 2 MB


def _clan_to_out(clan, member_count: int = 0) -> ClanOut:
    return ClanOut(
        id=clan.id,
        name=clan.name,
        slug=clan.slug,
        description=clan.description or "",
        emblem_path=clan.emblem_path,
        country_code=clan.country_code or "",
        region_name=clan.region_name or "",
        city_name=clan.city_name or "",
        district_name=clan.district_name or "",
        language=clan.language or "en",
        clan_type=clan.clan_type.value if hasattr(clan.clan_type, "value") else str(clan.clan_type),
        clan_mode=clan.clan_mode.value if hasattr(clan.clan_mode, "value") else str(clan.clan_mode),
        offline_friendly=bool(clan.offline_friendly),
        recruitment_mode=clan.recruitment_mode.value if hasattr(clan.recruitment_mode, "value") else str(clan.recruitment_mode),
        level=clan.level,
        experience=clan.experience,
        reputation=clan.reputation,
        treasury_currency=float(clan.treasury_currency or 0),
        member_limit=clan.member_limit,
        owner_id=clan.owner_id,
        created_at=clan.created_at,
        member_count=member_count,
    )


# ── Clan CRUD ─────────────────────────────────────────────────────────────────

@router.post("", response_model=ClanOut, summary="Create a new clan")
async def create_clan(
    body: ClanCreateIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    svc = ClanService(db)
    clan = await svc.create_clan(user["user_id"], body.model_dump())
    return _clan_to_out(clan, member_count=1)


@router.get("", response_model=List[ClanOut], summary="Search / list clans")
async def search_clans(
    country_code:     Optional[str]  = Query(None),
    region_name:      Optional[str]  = Query(None),
    city_name:        Optional[str]  = Query(None),
    clan_type:        Optional[str]  = Query(None),
    clan_mode:        Optional[str]  = Query(None),
    offline_friendly: Optional[bool] = Query(None),
    recruitment_mode: Optional[str]  = Query(None),
    min_level:        Optional[int]  = Query(None),
    max_level:        Optional[int]  = Query(None),
    limit:            int            = Query(20, ge=1, le=100),
    offset:           int            = Query(0, ge=0),
    db: AsyncSession = Depends(get_session),
):
    svc = ClanService(db)
    clans = await svc.search_clans(dict(
        country_code=country_code, region_name=region_name,
        city_name=city_name, clan_type=clan_type,
        clan_mode=clan_mode, offline_friendly=offline_friendly,
        recruitment_mode=recruitment_mode,
        min_level=min_level, max_level=max_level,
        limit=limit, offset=offset,
    ))
    return [_clan_to_out(c, len(c.members)) for c in clans]


@router.get("/{clan_id}", response_model=ClanOut, summary="Get clan details")
async def get_clan(
    clan_id: int,
    db: AsyncSession = Depends(get_session),
):
    svc = ClanService(db)
    clan = await svc.get_clan(clan_id)
    return _clan_to_out(clan, len(clan.members))


@router.patch("/{clan_id}", response_model=ClanOut, summary="Update clan settings")
async def update_clan(
    clan_id: int,
    body: ClanUpdateIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    svc = ClanService(db)
    clan = await svc.update_clan(clan_id, user["user_id"],
                                  body.model_dump(exclude_none=True))
    return _clan_to_out(clan)


@router.delete("/{clan_id}", summary="Disband clan (leader only)")
async def disband_clan(
    clan_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).disband_clan(clan_id, user["user_id"])
    return {"ok": True}


# ── Emblem ────────────────────────────────────────────────────────────────────

@router.post("/{clan_id}/emblem", summary="Upload clan emblem")
async def upload_emblem(
    clan_id: int,
    file: UploadFile = File(...),
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    svc = ClanService(db)
    from app.database.models.clan import ClanRole
    await svc._require_role(clan_id, user["user_id"],
                             [ClanRole.leader, ClanRole.co_leader])
    ext = Path(file.filename or "").suffix.lower()
    if ext not in ALLOWED_EMBLEM_EXT:
        raise HTTPException(400, f"Unsupported format: {ext}")
    data = await file.read()
    if len(data) > MAX_EMBLEM_BYTES:
        raise HTTPException(400, "File too large (max 2 MB)")
    filename = f"clan_{clan_id}{ext}"
    dest = EMBLEM_DIR / filename
    with open(dest, "wb") as f:
        f.write(data)
    clan = await svc.get_clan(clan_id)
    clan.emblem_path = str(dest)
    await db.commit()
    return {"ok": True, "path": str(dest)}


@router.delete("/{clan_id}/emblem", summary="Remove clan emblem")
async def delete_emblem(
    clan_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    svc = ClanService(db)
    from app.database.models.clan import ClanRole
    await svc._require_role(clan_id, user["user_id"], [ClanRole.leader])
    clan = await svc.get_clan(clan_id)
    if clan.emblem_path:
        try:
            os.remove(clan.emblem_path)
        except FileNotFoundError:
            pass
        clan.emblem_path = None
        await db.commit()
    return {"ok": True}


# ── Members ───────────────────────────────────────────────────────────────────

@router.get("/{clan_id}/members", response_model=List[ClanMemberOut],
            summary="List clan members")
async def get_members(
    clan_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    members = await ClanService(db).get_members(clan_id)
    return [ClanMemberOut.model_validate(m) for m in members]


@router.delete("/{clan_id}/members/{target_user_id}",
               summary="Kick a member")
async def kick_member(
    clan_id: int, target_user_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).kick_member(clan_id, user["user_id"], target_user_id)
    return {"ok": True}


@router.post("/{clan_id}/members/leave", summary="Leave the clan")
async def leave_clan(
    clan_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).leave_clan(clan_id, user["user_id"])
    return {"ok": True}


@router.patch("/{clan_id}/members/{target_user_id}/role",
              summary="Change member role")
async def update_role(
    clan_id: int, target_user_id: int,
    body: RoleUpdateIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).update_role(clan_id, user["user_id"],
                                       target_user_id, body.role)
    return {"ok": True}


@router.patch("/{clan_id}/members/{target_user_id}/nickname",
              summary="Set member call-sign")
async def update_nickname(
    clan_id: int, target_user_id: int,
    body: NicknameUpdateIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).update_nickname(clan_id, user["user_id"],
                                           target_user_id, body.nickname)
    return {"ok": True}


@router.patch("/{clan_id}/members/{target_user_id}/permissions",
              summary="Update granular permissions for a member")
async def update_permissions(
    clan_id: int, target_user_id: int,
    body: PermissionsUpdateIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).update_permissions(
        clan_id, user["user_id"], target_user_id,
        body.model_dump(exclude_none=True))
    return {"ok": True}


@router.post("/{clan_id}/transfer-leadership",
             summary="Transfer leadership to another member")
async def transfer_leadership(
    clan_id: int,
    body: TransferLeadershipIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).transfer_leadership(
        clan_id, user["user_id"], body.new_leader_user_id)
    return {"ok": True}


# ── Applications ──────────────────────────────────────────────────────────────

@router.post("/{clan_id}/applications",
             response_model=ApplicationOut, summary="Apply to a clan")
async def apply(
    clan_id: int,
    body: ApplicationIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    app = await ClanService(db).apply(clan_id, user["user_id"], body.model_dump())
    return ApplicationOut.model_validate(app)


@router.get("/{clan_id}/applications",
            response_model=List[ApplicationOut], summary="List applications")
async def list_applications(
    clan_id: int,
    status: Optional[str] = Query(None),
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    apps = await ClanService(db).list_applications(clan_id, user["user_id"], status)
    return [ApplicationOut.model_validate(a) for a in apps]


@router.post("/{clan_id}/applications/{app_id}/accept",
             summary="Accept an application")
async def accept_application(
    clan_id: int, app_id: int,
    body: ApplicationDecisionIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).accept_application(app_id, user["user_id"], body.decision_note)
    return {"ok": True}


@router.post("/{clan_id}/applications/{app_id}/reject",
             summary="Reject an application")
async def reject_application(
    clan_id: int, app_id: int,
    body: ApplicationDecisionIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).reject_application(app_id, user["user_id"], body.decision_note)
    return {"ok": True}


@router.post("/{clan_id}/applications/{app_id}/start-interview",
             summary="Move application to interview stage")
async def start_interview(
    clan_id: int, app_id: int,
    body: ApplicationDecisionIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).set_interview_status(
        app_id, user["user_id"], "interview", body.decision_note)
    return {"ok": True}


# ── Storage ───────────────────────────────────────────────────────────────────

@router.get("/{clan_id}/storage",
            response_model=List[StorageItemOut], summary="Get clan storage")
async def get_storage(
    clan_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    items = await ClanService(db).get_storage(clan_id)
    return [StorageItemOut.model_validate(i) for i in items]


@router.post("/{clan_id}/storage/deposit", summary="Deposit item into clan storage")
async def deposit(
    clan_id: int,
    body: StorageDepositIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).deposit(
        clan_id, user["user_id"], body.item_type, body.item_id, body.quantity, body.note)
    return {"ok": True}


@router.post("/{clan_id}/storage/withdraw", summary="Withdraw item from clan storage")
async def withdraw(
    clan_id: int,
    body: StorageWithdrawIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).withdraw(
        clan_id, user["user_id"], body.item_type, body.item_id, body.quantity, body.note)
    return {"ok": True}


@router.get("/{clan_id}/storage/logs",
            response_model=List[StorageTransactionOut],
            summary="Storage transaction log")
async def storage_logs(
    clan_id: int,
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    txs = await ClanService(db).get_storage_log(clan_id, limit)
    return [StorageTransactionOut.model_validate(t) for t in txs]


# ── Activity log ──────────────────────────────────────────────────────────────

@router.get("/{clan_id}/activity",
            response_model=List[ActivityLogOut], summary="Clan activity log")
async def activity_log(
    clan_id: int,
    limit: int = Query(50, le=200),
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    logs = await ClanService(db).get_activity_log(clan_id, limit)
    return [ActivityLogOut.model_validate(l) for l in logs]


# ── Meetup / QR ───────────────────────────────────────────────────────────────

@router.post("/{clan_id}/meetups",
             response_model=MeetupOut, summary="Create a clan meetup event")
async def create_meetup(
    clan_id: int,
    body: MeetupCreateIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    meetup = await ClanService(db).create_meetup(
        clan_id, user["user_id"], body.model_dump())
    return MeetupOut(
        id=meetup.id, clan_id=meetup.clan_id,
        title=meetup.title, description=meetup.description or "",
        city_name=meetup.city_name or "",
        scheduled_at=meetup.scheduled_at,
        status=meetup.status.value if hasattr(meetup.status, "value") else str(meetup.status),
        created_at=meetup.created_at, participant_count=0,
    )


@router.get("/{clan_id}/meetups",
            response_model=List[MeetupOut], summary="List clan meetups")
async def list_meetups(
    clan_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    meetups = await ClanService(db).list_meetups(clan_id)
    return [
        MeetupOut(
            id=m.id, clan_id=m.clan_id,
            title=m.title, description=m.description or "",
            city_name=m.city_name or "",
            scheduled_at=m.scheduled_at,
            status=m.status.value if hasattr(m.status, "value") else str(m.status),
            created_at=m.created_at,
            participant_count=len(m.participants),
        )
        for m in meetups
    ]


@router.post("/meetups/{meetup_id}/generate-qr", summary="Generate QR for meetup check-in")
async def generate_qr(
    meetup_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    return await ClanService(db).generate_qr(meetup_id, user["user_id"])


@router.post("/meetups/{meetup_id}/check-in", summary="Check in via QR token")
async def check_in(
    meetup_id: int,
    body: QRCheckInIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    return await ClanService(db).check_in(meetup_id, user["user_id"], body.qr_token)


@router.post("/meetups/{meetup_id}/close", summary="Close a meetup event")
async def close_meetup(
    meetup_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    await ClanService(db).close_meetup(meetup_id, user["user_id"])
    return {"ok": True}


# ── Raid Tickets ──────────────────────────────────────────────────────────────

@router.get("/raid-tickets/my",
            response_model=List[RaidTicketOut], summary="My raid tickets")
async def my_raid_tickets(
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    res = await db.execute(
        select(RaidTicket).where(
            RaidTicket.owner_user_id == user["user_id"],
            RaidTicket.owner_type == TicketOwnerType.user,
        )
    )
    tickets = res.scalars().all()
    return [RaidTicketOut.model_validate(t) for t in tickets]


from pydantic import BaseModel as _BaseModel

# ── Chat history ──────────────────────────────────────────────────────────────

class ChatMessageOut(_BaseModel):
    id:             int
    sender_user_id: Optional[int]
    message_type:   str
    content:        str
    created_at:     str

    model_config = {"from_attributes": True}


@router.get("/{clan_id}/chat/history",
            summary="Fetch recent clan chat messages")
async def chat_history(
    clan_id: int,
    limit:   int = Query(50, le=200),
    before_id: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    # Must be a member
    from app.services.clan import ClanService
    await ClanService(db)._get_member(clan_id, user["user_id"])

    stmt = (
        select(ClanChatMessage)
        .where(ClanChatMessage.clan_id == clan_id)
        .order_by(ClanChatMessage.created_at.desc())
        .limit(limit)
    )
    if before_id:
        stmt = stmt.where(ClanChatMessage.id < before_id)
    res = await db.execute(stmt)
    msgs = list(reversed(res.scalars().all()))
    return [
        {
            "id":             m.id,
            "sender_user_id": m.sender_user_id,
            "message_type":   m.message_type,
            "content":        m.content,
            "created_at":     m.created_at.isoformat(),
        }
        for m in msgs
    ]


# ── Clan Craft ────────────────────────────────────────────────────────────────

@router.get("/{clan_id}/craft/recipes",
            summary="List recipes usable with clan storage resources")
async def clan_craft_recipes(
    clan_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    from app.services.clan import ClanService
    from sqlalchemy.orm import selectinload as _si
    # Must be a clan member with craft permission
    svc  = ClanService(db)
    member = await svc._get_member(clan_id, user["user_id"])
    from app.database.models.clan import ClanRole
    can_craft = (
        member.can_craft_storage
        or member.role in (ClanRole.leader, ClanRole.co_leader,
                           ClanRole.quartermaster, ClanRole.crafter)
    )
    if not can_craft:
        raise HTTPException(403, "No craft permission for clan storage")

    # Load all recipes with their resource requirements
    res = await db.execute(
        select(CraftRecipe).options(_si(CraftRecipe.resources))
    )
    recipes = res.scalars().all()

    # Load current clan storage
    storage_items = await svc.get_storage(clan_id)
    storage_map = {
        (s.item_type, s.item_id): s.quantity - s.reserved_quantity
        for s in storage_items
    }

    result = []
    for recipe in recipes:
        ingredients = []
        can_start   = True
        for req in recipe.resources:
            avail = storage_map.get(("resource", req.resource_id), 0)
            has   = avail >= req.quantity
            if not has:
                can_start = False
            ingredients.append({
                "resource_id": req.resource_id,
                "quantity":    req.quantity,
                "type":        req.type,
                "available":   avail,
                "satisfied":   has,
            })
        result.append({
            "id":             recipe.id,
            "name":           recipe.name,
            "item_type":      recipe.item_type,
            "grade":          recipe.grade,
            "craft_time_sec": recipe.craft_time_sec,
            "result_item_id": recipe.result_item_id,
            "ingredients":    ingredients,
            "can_start":      can_start,
        })
    return result


class ClanCraftStartIn(_BaseModel):
    recipe_id:    int
    deliver_to_storage: bool = False   # if True, result goes to clan storage


@router.post("/{clan_id}/craft/start",
             summary="Start a craft job using clan storage resources")
async def clan_craft_start(
    clan_id: int,
    body:    ClanCraftStartIn,
    db:      AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    from app.services.clan import ClanService
    from sqlalchemy.orm import selectinload as _si
    from datetime import timedelta

    svc    = ClanService(db)
    member = await svc._get_member(clan_id, user["user_id"])
    from app.database.models.clan import ClanRole
    can_craft = (
        member.can_craft_storage
        or member.role in (ClanRole.leader, ClanRole.co_leader,
                           ClanRole.quartermaster, ClanRole.crafter)
    )
    if not can_craft:
        raise HTTPException(403, "No craft permission")

    # Load recipe
    res = await db.execute(
        select(CraftRecipe)
        .where(CraftRecipe.id == body.recipe_id)
        .options(_si(CraftRecipe.resources))
    )
    recipe = res.scalars().first()
    if not recipe:
        raise HTTPException(404, "Recipe not found")

    from app.database.models.clan import ClanStorageItem as _CSI, StorageAction

    # Verify sufficient stock for all ingredients first
    for req in recipe.resources:
        row = await db.execute(
            select(_CSI).where(
                _CSI.clan_id   == clan_id,
                _CSI.item_type == "resource",
                _CSI.item_id   == req.resource_id,
            )
        )
        sr        = row.scalars().first()
        available = (sr.quantity - sr.reserved_quantity) if sr else 0
        if available < req.quantity:
            raise HTTPException(400,
                f"Not enough resource id={req.resource_id} in clan storage "
                f"(need {req.quantity}, have {available})")

    # Deduct quantities
    for req in recipe.resources:
        row = await db.execute(
            select(_CSI).where(
                _CSI.clan_id   == clan_id,
                _CSI.item_type == "resource",
                _CSI.item_id   == req.resource_id,
            )
        )
        sr = row.scalars().first()
        sr.quantity -= req.quantity
        svc._add_tx(clan_id, user["user_id"], StorageAction.craft,
                    "resource", req.resource_id, req.quantity,
                    f"craft recipe {recipe.id}")

    # Create craft queue entry for the user
    from datetime import timedelta
    ready_at = datetime.utcnow() + timedelta(seconds=recipe.craft_time_sec or 60)
    cq = CraftQueue()
    cq.user_id   = user["user_id"]
    cq.recipe_id = recipe.id
    cq.ready_at  = ready_at
    db.add(cq)

    await db.commit()
    await db.refresh(cq)
    return {
        "ok":            True,
        "craft_queue_id": cq.id,
        "ready_at":       ready_at.isoformat(),
        "deliver_to_storage": body.deliver_to_storage,
    }
