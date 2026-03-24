"""Alliance Router"""
from __future__ import annotations

from typing import Any, Dict, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.session import get_session
from app.auth import get_current_user_info
from app.services.alliance_service import AllianceService


router = APIRouter(prefix="/alliances", tags=["Alliances"])


class CreateAllianceIn(BaseModel):
    name:             str = Field(..., min_length=3, max_length=128)
    tag:              str = Field(..., min_length=2, max_length=8)
    description:      str = ""
    founding_clan_id: int


class InviteClanIn(BaseModel):
    clan_id: int


class LeaveClanIn(BaseModel):
    clan_id: int


class DepositIn(BaseModel):
    clan_id:   int
    currency:  int = Field(0, ge=0)
    resources: Optional[Dict[str, int]] = None


@router.post("")
async def create_alliance(
    body:      CreateAllianceIn,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc = AllianceService(db)
    try:
        alliance = await svc.create_alliance(
            name=body.name, tag=body.tag, description=body.description,
            founding_clan_id=body.founding_clan_id, user_id=user_info["user_id"],
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    return await svc.get_summary(alliance.id)


@router.get("")
async def list_alliances(
    offset: int = Query(0, ge=0),
    limit:  int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc       = AllianceService(db)
    alliances = await svc.list_alliances(offset, limit)
    summaries = []
    for a in alliances:
        try:
            summaries.append(await svc.get_summary(a.id))
        except Exception:
            pass
    return {"alliances": summaries, "total": len(summaries)}


@router.get("/clan/{clan_id}")
async def alliance_for_clan(
    clan_id: int,
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc      = AllianceService(db)
    alliance = await svc.get_alliance_for_clan(clan_id)
    if not alliance:
        raise HTTPException(404, "Clan is not in any alliance")
    return await svc.get_summary(alliance.id)


@router.get("/{alliance_id}")
async def get_alliance(
    alliance_id: int,
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc = AllianceService(db)
    try:
        return await svc.get_summary(alliance_id)
    except ValueError as exc:
        raise HTTPException(404, str(exc))


@router.get("/{alliance_id}/members")
async def alliance_members(
    alliance_id: int,
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc     = AllianceService(db)
    members = await svc.get_members(alliance_id)
    return {
        "alliance_id": alliance_id,
        "members": [
            {"clan_id": m.clan_id, "role": m.role.value,
             "joined_at": m.joined_at.isoformat(), "contribution": m.contribution}
            for m in members
        ]
    }


@router.get("/{alliance_id}/war-chest")
async def war_chest(
    alliance_id: int,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc   = AllianceService(db)
    chest = await svc.get_war_chest(alliance_id)
    if not chest:
        raise HTTPException(404, "War chest not found")
    return {
        "alliance_id":    alliance_id,
        "currency":       chest.currency,
        "resources":      chest.resources,
        "pending_income": chest.pending_income,
        "last_upkeep_at": chest.last_upkeep_at.isoformat() if chest.last_upkeep_at else None,
    }


@router.post("/{alliance_id}/invite")
async def invite_clan(
    alliance_id: int,
    body:        InviteClanIn,
    user_info:   dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc = AllianceService(db)
    try:
        member = await svc.invite_clan(alliance_id, body.clan_id, user_info["user_id"])
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    return {"alliance_id": alliance_id, "clan_id": member.clan_id,
            "role": member.role.value, "message": "Clan invited to the alliance."}


@router.post("/{alliance_id}/leave")
async def leave_alliance(
    alliance_id: int,
    body:        LeaveClanIn,
    user_info:   dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc = AllianceService(db)
    try:
        await svc.leave_alliance(alliance_id, body.clan_id, user_info["user_id"])
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    return {"message": "Clan left the alliance."}


@router.post("/{alliance_id}/war-chest/deposit")
async def deposit(
    alliance_id: int,
    body:        DepositIn,
    user_info:   dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc = AllianceService(db)
    try:
        chest = await svc.deposit_to_chest(
            alliance_id=alliance_id, clan_id=body.clan_id,
            user_id=user_info["user_id"], currency=body.currency,
            resources=body.resources,
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    return {"alliance_id": alliance_id, "chest_currency": chest.currency,
            "chest_resources": chest.resources}


@router.post("/{alliance_id}/upkeep")
async def run_upkeep(
    alliance_id: int,
    user_info:   dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    if user_info.get("role") not in ("admin", "moderator"):
        raise HTTPException(403, "Admin only")
    return await AllianceService(db).process_upkeep_tick(alliance_id)
