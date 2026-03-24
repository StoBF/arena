"""Resurrection Router"""
from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.session import get_session
from app.auth import get_current_user_info
from app.services.resurrection_service import ResurrectionService


router = APIRouter(prefix="/resurrection", tags=["Resurrection"])


class MarkDeadIn(BaseModel):
    hero_id:     int
    death_cause: str = "killed_in_battle"


@router.get("/{hero_id}/status")
async def resurrection_status(
    hero_id:   int,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    try:
        return await ResurrectionService(db).get_resurrection_status(hero_id)
    except ValueError as exc:
        raise HTTPException(404, str(exc))


@router.post("/{hero_id}/attempt")
async def attempt_resurrection(
    hero_id:   int,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    try:
        return await ResurrectionService(db).attempt_craft(hero_id, user_info["user_id"])
    except ValueError as exc:
        raise HTTPException(400, str(exc))


@router.post("/admin/mark-dead")
async def admin_mark_dead(
    body:      MarkDeadIn,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    if user_info.get("role") not in ("admin", "moderator"):
        raise HTTPException(403, "Admin only")
    svc  = ResurrectionService(db)
    hero = await svc.mark_dead(body.hero_id, body.death_cause)
    return {
        "hero_id":   hero.id, "hero_name": hero.name,
        "is_dead":   hero.is_dead, "death_cause": hero.death_cause,
        "message":   "Hero marked as dead. 7-day resurrection window is open.",
    }


@router.post("/admin/expire")
async def admin_expire_dead(
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    if user_info.get("role") not in ("admin",):
        raise HTTPException(403, "Admin only")
    expired = await ResurrectionService(db).expire_dead_heroes()
    return {"expired_count": len(expired), "hero_ids": expired}
