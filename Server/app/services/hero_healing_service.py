"""
Hero Healing Service
======================
Body part injuries reduce hero effectiveness in battle.
Healing takes real time; gold speeds it up.

Body Part → Stat Penalty Table:
  head         → -25% skill accuracy, -15% stamina
  torso        → -20% HP, -10% armor
  left_arm     → -15% attack damage
  right_arm    → -20% attack damage
  left_leg     → -20% speed
  right_leg    → -25% speed

Severity modifiers:
  INJURED          → 50% of penalty
  SEVERELY_INJURED → 100% of penalty

Конфіг часу та вартості лікування: config/game_config.yaml → healing
"""
from __future__ import annotations

import math
from datetime import datetime, timedelta
from decimal import Decimal
from typing import Dict, List, Optional

from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.game_config import cfg
from app.database.models.game_systems import HeroHealOrder, HealStatus
from app.database.models.hero import HeroBodyPart, BodyPartStatus


PART_PENALTIES: Dict[str, Dict[str, float]] = {
    "head":      {"skill_accuracy": -0.25, "stamina": -0.15},
    "torso":     {"max_hp": -0.20, "armor": -0.10},
    "left_arm":  {"attack": -0.15},
    "right_arm": {"attack": -0.20},
    "left_leg":  {"speed": -0.20},
    "right_leg": {"speed": -0.25},
}


class HeroHealingService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Start heal ────────────────────────────────────────────────────────────
    async def start_heal(
        self,
        hero_id:   int,
        user_id:   int,
        part_name: str,
    ) -> HeroHealOrder:
        part = await self._get_body_part(hero_id, part_name)
        if not part:
            raise ValueError(f"Body part '{part_name}' not found for hero {hero_id}")
        if part.status == BodyPartStatus.HEALTHY:
            raise ValueError(f"'{part_name}' is already healthy")

        result = await self.db.execute(
            select(HeroHealOrder).where(
                and_(HeroHealOrder.hero_id   == hero_id,
                     HeroHealOrder.part_name == part_name,
                     HeroHealOrder.status    == HealStatus.in_progress)
            )
        )
        if result.scalar_one_or_none():
            raise ValueError(f"'{part_name}' is already being healed")

        severity = part.status.value.lower()
        duration = cfg.healing.duration(severity, part_name)
        cost     = cfg.healing.cost(severity, part_name)

        from app.database.models.user import User
        user = await self.db.get(User, user_id)
        if not user or float(user.balance or 0) < cost:
            raise ValueError(
                f"Need {cost} gold to start healing "
                f"(have {float(user.balance or 0) if user else 0})"
            )
        user.balance = float(user.balance) - cost

        now = datetime.utcnow()
        order = HeroHealOrder(
            hero_id           = hero_id,
            user_id           = user_id,
            part_name         = part_name,
            severity          = severity,
            heal_duration_sec = duration,
            started_at        = now,
            completes_at      = now + timedelta(seconds=duration),
            gold_spent        = Decimal(str(cost)),
            status            = HealStatus.in_progress,
        )
        self.db.add(order)
        await self.db.commit()
        await self.db.refresh(order)
        return order

    # ── Speed up with gold ────────────────────────────────────────────────────
    async def speedup_with_gold(
        self,
        user_id:  int,
        order_id: int,
        hours:    int,
    ) -> HeroHealOrder:
        """
        Прискорення лікування за gold.
        Вартість: cfg.healing.speedup_gold_per_hour × hours.
        """
        order = await self.db.get(HeroHealOrder, order_id)
        if not order or order.user_id != user_id:
            raise ValueError("Heal order not found")
        if order.status != HealStatus.in_progress:
            raise ValueError("Heal order is not in progress")

        now = datetime.utcnow()
        remaining_sec = max(0.0, (order.completes_at - now).total_seconds())
        if remaining_sec <= 0:
            await self._complete_heal(order)
            await self.db.commit()
            return order

        max_hours  = math.ceil(remaining_sec / 3600)
        hours      = min(hours, max_hours)
        gold_cost  = hours * cfg.healing.speedup_gold_per_hour

        from app.database.models.user import User
        user = await self.db.get(User, user_id)
        if not user or float(user.balance or 0) < gold_cost:
            raise ValueError(f"Need {gold_cost} gold to speed up (have {float(user.balance or 0) if user else 0})")

        user.balance = float(user.balance) - gold_cost
        order.gold_spent = Decimal(str(float(order.gold_spent or 0) + gold_cost))

        skip_sec   = hours * 3600
        order.completes_at = order.completes_at - timedelta(seconds=skip_sec)
        if order.completes_at <= now:
            await self._complete_heal(order)

        await self.db.commit()
        await self.db.refresh(order)
        return order

    # ── Tick: complete ready heal orders ──────────────────────────────────────
    async def tick(self) -> List[HeroHealOrder]:
        now = datetime.utcnow()
        result = await self.db.execute(
            select(HeroHealOrder).where(
                and_(HeroHealOrder.status       == HealStatus.in_progress,
                     HeroHealOrder.completes_at <= now)
            )
        )
        completed = []
        for order in result.scalars().all():
            await self._complete_heal(order)
            completed.append(order)
        if completed:
            await self.db.commit()
        return completed

    async def _complete_heal(self, order: HeroHealOrder) -> None:
        part = await self._get_body_part(order.hero_id, order.part_name)
        if part:
            part.status = BodyPartStatus.HEALTHY
        order.status       = HealStatus.completed
        order.completed_at = datetime.utcnow()
        await self._recalculate_hero_condition(order.hero_id)

    async def _recalculate_hero_condition(self, hero_id: int) -> None:
        from app.database.models.hero import Hero, HeroCondition
        result = await self.db.execute(
            select(HeroBodyPart).where(HeroBodyPart.hero_id == hero_id)
        )
        parts    = list(result.scalars().all())
        statuses = [p.status for p in parts]

        if all(s == BodyPartStatus.HEALTHY for s in statuses):
            condition = HeroCondition.HEALTHY
        elif any(s == BodyPartStatus.SEVERELY_INJURED for s in statuses):
            condition = HeroCondition.SEVERELY_INJURED
        elif any(s == BodyPartStatus.INJURED for s in statuses):
            condition = HeroCondition.WOUNDED
        else:
            condition = HeroCondition.HEALTHY

        hero = await self.db.get(Hero, hero_id)
        if hero:
            hero.condition = condition

    # ── Effective stat penalties ───────────────────────────────────────────────
    async def get_effective_stat_penalties(self, hero_id: int) -> Dict[str, float]:
        result = await self.db.execute(
            select(HeroBodyPart).where(HeroBodyPart.hero_id == hero_id)
        )
        parts  = list(result.scalars().all())
        totals: Dict[str, float] = {}

        for part in parts:
            if part.status == BodyPartStatus.HEALTHY:
                continue
            severity_mult = 0.5 if part.status == BodyPartStatus.INJURED else 1.0
            penalties = PART_PENALTIES.get(part.part_name, {})
            for stat, penalty in penalties.items():
                totals[stat] = totals.get(stat, 0.0) + penalty * severity_mult

        return {k: max(-0.80, v) for k, v in totals.items()}

    # ── Read ──────────────────────────────────────────────────────────────────
    async def get_hero_heal_status(self, hero_id: int) -> Dict:
        result = await self.db.execute(
            select(HeroBodyPart).where(HeroBodyPart.hero_id == hero_id)
        )
        parts = list(result.scalars().all())

        orders_result = await self.db.execute(
            select(HeroHealOrder).where(
                and_(HeroHealOrder.hero_id == hero_id,
                     HeroHealOrder.status  == HealStatus.in_progress)
            )
        )
        active_orders = list(orders_result.scalars().all())
        now = datetime.utcnow()

        return {
            "body_parts": [
                {
                    "part":               p.part_name,
                    "status":             p.status.value,
                    "penalty":            PART_PENALTIES.get(p.part_name, {}),
                    "heal_cost_gold":     cfg.healing.cost(p.status.value.lower(), p.part_name),
                    "heal_duration_sec":  cfg.healing.duration(p.status.value.lower(), p.part_name),
                }
                for p in parts
            ],
            "active_heals": [
                {
                    "order_id":           o.id,
                    "part_name":          o.part_name,
                    "completes_at":       o.completes_at.isoformat(),
                    "remaining_sec":      max(0, int((o.completes_at - now).total_seconds())),
                    "speedup_gold_cost":  cfg.healing.speedup_cost(
                        max(0, (o.completes_at - now).total_seconds())
                    ),
                }
                for o in active_orders
            ],
            "stat_penalties": await self.get_effective_stat_penalties(hero_id),
        }

    async def _get_body_part(
        self, hero_id: int, part_name: str
    ) -> Optional[HeroBodyPart]:
        result = await self.db.execute(
            select(HeroBodyPart).where(
                and_(HeroBodyPart.hero_id   == hero_id,
                     HeroBodyPart.part_name == part_name)
            )
        )
        return result.scalar_one_or_none()
