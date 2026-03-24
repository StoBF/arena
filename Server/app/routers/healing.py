"""
Hero Healing Router
====================
Все лікування платиться ігровим золотом.
Вартість та тривалість: config/game_config.yaml → healing
"""
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_info
from app.core.game_config import cfg
from app.database.session import get_session
from app.services.hero_healing_service import HeroHealingService


router = APIRouter(prefix="/healing", tags=["Hero Healing"])


class StartHealIn(BaseModel):
    part_name: str = Field(..., description="head | torso | left_arm | right_arm | left_leg | right_leg")


class SpeedupIn(BaseModel):
    hours: int = Field(..., ge=1, description="How many hours of heal time to skip (paid in gold)")


async def _assert_owner(hero_id: int, user_id: int, db: AsyncSession) -> None:
    from app.database.models.hero import Hero
    hero = await db.get(Hero, hero_id)
    if not hero:
        raise HTTPException(404, "Hero not found")
    if hero.owner_id != user_id:
        raise HTTPException(403, "You don't own this hero")


@router.get("/{hero_id}/status")
async def heal_status(
    hero_id:   int,
    user_info: dict = Depends(get_current_user_info),
    db:        AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    """
    Статус здоров'я героя: всі частини тіла, активні замовлення на лікування, поточні штрафи.
    """
    await _assert_owner(hero_id, user_info["user_id"], db)
    return await HeroHealingService(db).get_hero_heal_status(hero_id)


@router.post("/{hero_id}/start")
async def start_heal(
    hero_id:   int,
    body:      StartHealIn,
    user_info: dict = Depends(get_current_user_info),
    db:        AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    """
    Запустити лікування частини тіла. Списується золото з балансу.
    Час лікування та вартість: game_config.yaml → healing.
    """
    await _assert_owner(hero_id, user_info["user_id"], db)
    svc = HeroHealingService(db)
    try:
        order = await svc.start_heal(hero_id, user_info["user_id"], body.part_name)
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    return {
        "order_id":     order.id,
        "part_name":    order.part_name,
        "severity":     order.severity,
        "completes_at": order.completes_at.isoformat(),
        "gold_spent":   float(order.gold_spent),
        "message":      f"Healing {order.part_name} — completes in {order.heal_duration_sec // 60} min.",
    }


@router.post("/orders/{order_id}/speedup")
async def speedup_heal(
    order_id:  int,
    body:      SpeedupIn,
    user_info: dict = Depends(get_current_user_info),
    db:        AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    """
    Прискорити лікування за золото.
    Вартість: {speedup_gold_per_hour} gold × hours (game_config.yaml → healing.speedup_gold_per_hour).
    """
    svc = HeroHealingService(db)
    try:
        order = await svc.speedup_with_gold(user_info["user_id"], order_id, body.hours)
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    remaining = max(0, int((order.completes_at - datetime.utcnow()).total_seconds()))
    return {
        "order_id":         order.id,
        "hours_skipped":    body.hours,
        "gold_per_hour":    cfg.healing.speedup_gold_per_hour,
        "new_completes_at": order.completes_at.isoformat(),
        "remaining_sec":    remaining,
        "completed":        order.status.value == "completed",
    }


@router.get("/{hero_id}/penalties")
async def stat_penalties(
    hero_id:   int,
    user_info: dict = Depends(get_current_user_info),
    db:        AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    """Поточні бойові штрафи через травми. Всі значення від'ємні (%)."""
    svc      = HeroHealingService(db)
    penalties = await svc.get_effective_stat_penalties(hero_id)
    return {
        "hero_id":  hero_id,
        "penalties": penalties,
        "note":      "Negative values are % reductions applied during battle",
    }
