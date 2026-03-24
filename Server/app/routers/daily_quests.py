"""Daily Quest Router"""
from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.session import get_session
from app.auth import get_current_user_info
from app.services.daily_quest_service import DailyQuestService


router = APIRouter(prefix="/quests", tags=["Daily Quests"])


class RecordActionIn(BaseModel):
    action: str
    amount: int = 1


@router.get("/status")
async def quest_status(
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc = DailyQuestService(db)
    await svc.assign_daily_quests(user_info["user_id"])
    return await svc.get_player_status(user_info["user_id"])


@router.post("/assign")
async def assign_quests(
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc    = DailyQuestService(db)
    quests = await svc.assign_daily_quests(user_info["user_id"])
    return {"assigned": len(quests)}


@router.post("/login")
async def record_login(
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc    = DailyQuestService(db)
    streak = await svc.track_login(user_info["user_id"])
    reward = None

    if streak.login_streak % 7 == 0:
        bonus = 500 * (streak.login_streak // 7)
        from app.database.models.user import User
        user = await db.get(User, user_info["user_id"])
        if user:
            user.balance = float(user.balance or 0) + bonus
            await db.commit()
        reward = {"type": "currency", "amount": bonus,
                  "note": f"{streak.login_streak}-day login streak!"}

    return {
        "login_streak":     streak.login_streak,
        "max_login_streak": streak.max_login_streak,
        "streak_reward":    reward,
    }


@router.post("/{quest_id}/claim")
async def claim_quest_reward(
    quest_id: int,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc = DailyQuestService(db)
    try:
        return await svc.claim_reward(user_info["user_id"], quest_id)
    except ValueError as exc:
        raise HTTPException(400, str(exc))


@router.post("/progress")
async def record_action(
    body: RecordActionIn,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc       = DailyQuestService(db)
    completed = await svc.record_action(user_info["user_id"], body.action, body.amount)
    return {"newly_completed": [q.id for q in completed], "count": len(completed)}


@router.get("/templates")
async def list_templates(
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    from sqlalchemy import select
    from app.database.models.game_systems import DailyQuestTemplate
    result    = await db.execute(select(DailyQuestTemplate).order_by(DailyQuestTemplate.id))
    templates = result.scalars().all()
    return {
        "templates": [
            {"id": t.id, "code": t.code, "title": t.title,
             "category": t.category.value, "frequency": t.frequency.value,
             "task": t.task, "rewards": t.rewards,
             "xp_reward": t.xp_reward, "is_active": t.is_active}
            for t in templates
        ]
    }


@router.post("/seed")
async def seed_templates(
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    if user_info.get("role") not in ("admin", "moderator"):
        raise HTTPException(403, "Admin only")
    svc   = DailyQuestService(db)
    added = await svc.seed_templates()
    return {"added": added}
