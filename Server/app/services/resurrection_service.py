"""
Resurrection Service
======================
When a hero dies in battle, a 7-day window opens to resurrect them.
Усі параметри (вікно, шанс крафту, матеріали, вартість золота) — в game_config.yaml.

Flow:
  1. Craft the Phoenix Core artifact (5% success chance per attempt, за замовчуванням).
  2. Materials consumed on EVERY attempt (success or fail).
  3. On success: hero revives at 30% HP, all body parts SEVERELY_INJURED.
  4. Cost scales +20% per prior resurrection_count.
"""
from __future__ import annotations

import random
from datetime import datetime, timedelta
from typing import Dict, List

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.game_config import cfg
from app.database.models.game_systems import ResurrectionAttempt
from app.database.models.hero import Hero, HeroCondition, HeroBodyPart, BodyPartStatus


class ResurrectionService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Check eligibility ──────────────────────────────────────────────────────
    async def get_resurrection_status(self, hero_id: int) -> Dict:
        hero = await self.db.get(Hero, hero_id)
        if not hero:
            raise ValueError("Hero not found")
        if not hero.is_dead:
            return {"eligible": False, "reason": "Hero is alive"}

        died_at = getattr(hero, "dead_at", None)
        if not died_at:
            return {"eligible": False, "reason": "No death record found"}

        window_days = cfg.resurrection.window_days
        deadline    = died_at + timedelta(days=window_days)
        now         = datetime.utcnow()

        if now > deadline:
            return {
                "eligible":   False,
                "reason":     "Resurrection window expired",
                "died_at":    died_at.isoformat(),
                "expired_at": deadline.isoformat(),
            }

        remaining_hours = int((deadline - now).total_seconds() / 3600)

        count     = hero.resurrection_count or 0
        cost_mult = 1.0 + count * cfg.resurrection.cost_escalation_per_revival
        materials = {k: int(v * cost_mult) for k, v in cfg.resurrection.base_materials.items()}
        gold_cost = int(cfg.resurrection.base_gold_cost * cost_mult)

        return {
            "eligible":           True,
            "hero_id":            hero_id,
            "hero_name":          hero.name,
            "died_at":            died_at.isoformat(),
            "deadline":           deadline.isoformat(),
            "remaining_hours":    remaining_hours,
            "success_chance_pct": int(cfg.resurrection.base_success_chance * 100),
            "resurrection_count": count,
            "cost_multiplier":    round(cost_mult, 2),
            "required_materials": materials,
            "required_gold":      gold_cost,
        }

    # ── Attempt craft ──────────────────────────────────────────────────────────
    async def attempt_craft(
        self,
        hero_id: int,
        user_id: int,
    ) -> Dict:
        """
        Deducts materials and gold regardless of outcome.
        Returns whether craft succeeded and whether the hero is now revived.
        """
        status = await self.get_resurrection_status(hero_id)
        if not status.get("eligible"):
            raise ValueError(status.get("reason", "Not eligible"))

        hero = await self.db.get(Hero, hero_id)
        if hero.owner_id != user_id:
            raise ValueError("You don't own this hero")

        materials = status["required_materials"]
        gold_cost = status["required_gold"]

        await self._deduct_materials(user_id, materials, gold_cost)

        roll      = random.random()
        succeeded = roll < cfg.resurrection.base_success_chance

        attempt = ResurrectionAttempt(
            hero_id         = hero_id,
            user_id         = user_id,
            craft_roll      = round(roll, 6),
            craft_succeeded = succeeded,
            craft_materials = [
                {"resource": k, "qty": v} for k, v in materials.items()
            ] + [{"resource": "gold", "qty": gold_cost}],
            gold_paid       = gold_cost,
        )
        self.db.add(attempt)

        if succeeded:
            await self._revive_hero(hero, attempt)
            result_msg = "Phoenix Core forged successfully! Hero is being revived."
        else:
            result_msg = (
                "The ritual failed. All materials were consumed by the void. "
                "You may try again while the window is open."
            )

        await self.db.commit()
        await self.db.refresh(attempt)

        return {
            "attempt_id":     attempt.id,
            "roll":           round(roll, 4),
            "succeeded":      succeeded,
            "hero_revived":   succeeded,
            "message":        result_msg,
            "remaining_hours": status["remaining_hours"],
        }

    # ── Revive hero ────────────────────────────────────────────────────────────
    async def _revive_hero(self, hero: Hero, attempt: ResurrectionAttempt) -> None:
        hero.is_dead            = False
        hero.condition          = HeroCondition.SEVERELY_INJURED
        hero.resurrection_count = (hero.resurrection_count or 0) + 1

        if hasattr(hero, "dead_at"):
            hero.dead_at = None

        result = await self.db.execute(
            select(HeroBodyPart).where(HeroBodyPart.hero_id == hero.id)
        )
        for part in result.scalars().all():
            part.status = BodyPartStatus.SEVERELY_INJURED

        attempt.used_at         = datetime.utcnow()
        attempt.resurrection_ok = True
        attempt.notes           = f"Hero resurrected (attempt #{hero.resurrection_count})"

    # ── Mark hero dead (called from battle service) ────────────────────────────
    async def mark_dead(
        self,
        hero_id:     int,
        death_cause: str = "killed_in_battle",
    ) -> Hero:
        hero = await self.db.get(Hero, hero_id)
        if not hero:
            raise ValueError("Hero not found")

        hero.is_dead     = True
        hero.death_cause = death_cause
        hero.total_deaths = (hero.total_deaths or 0) + 1

        if hasattr(hero, "dead_at"):
            hero.dead_at = datetime.utcnow()

        result = await self.db.execute(
            select(HeroBodyPart).where(HeroBodyPart.hero_id == hero_id)
        )
        for part in result.scalars().all():
            part.status = BodyPartStatus.SEVERELY_INJURED

        await self.db.commit()
        await self.db.refresh(hero)
        return hero

    # ── Expire dead heroes (cron job) ─────────────────────────────────────────
    async def expire_dead_heroes(self) -> List[int]:
        """Called by a scheduler every hour. Returns IDs of expired heroes."""
        from sqlalchemy import and_

        deadline_cutoff = datetime.utcnow() - timedelta(days=cfg.resurrection.window_days)

        result = await self.db.execute(
            select(Hero).where(Hero.is_dead == True)
        )
        expired = []
        for hero in result.scalars().all():
            dead_at = getattr(hero, "dead_at", None)
            if dead_at and dead_at < deadline_cutoff:
                expired.append(hero.id)
                if hasattr(hero, "deleted_at"):
                    hero.deleted_at = datetime.utcnow()
                hero.death_cause = "permanent_death:window_expired"

        if expired:
            await self.db.commit()
        return expired

    # ── Inventory helper ───────────────────────────────────────────────────────
    async def _deduct_materials(
        self,
        user_id:   int,
        materials: Dict[str, int],
        gold_cost: int,
    ) -> None:
        from sqlalchemy import and_
        from app.database.models.user import User
        from app.database.models.resource import GameResource
        from app.database.models.battle_room import PlayerResourceInventory

        user = await self.db.get(User, user_id)
        if not user:
            raise ValueError("User not found")
        if float(user.balance or 0) < gold_cost:
            raise ValueError(
                f"Insufficient gold. Need {gold_cost}, have {user.balance}"
            )
        user.balance = float(user.balance) - gold_cost

        for resource_code, qty_needed in materials.items():
            res_result = await self.db.execute(
                select(GameResource).where(GameResource.code == resource_code)
            )
            catalog = res_result.scalar_one_or_none()
            if not catalog:
                raise ValueError(f"Unknown resource: {resource_code}")

            inv_result = await self.db.execute(
                select(PlayerResourceInventory).where(
                    and_(
                        PlayerResourceInventory.user_id     == user_id,
                        PlayerResourceInventory.resource_id == catalog.id,
                    )
                )
            )
            inv  = inv_result.scalar_one_or_none()
            have = inv.quantity if inv else 0
            if have < qty_needed:
                raise ValueError(
                    f"Insufficient {resource_code}: need {qty_needed}, have {have}"
                )
            inv.quantity -= qty_needed
