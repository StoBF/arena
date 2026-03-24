# app/services/hero.py
"""
Hero service — v2 (role-based, skill catalog, no training/XP).

CRUD operations, generation orchestration, and relationship loading.
"""

from sqlalchemy.future import select
from sqlalchemy import func
from datetime import datetime, timedelta
from fastapi import HTTPException
from app.database.models.hero import Hero, HeroCondition
from app.database.models.user import User
from app.services.base_service import BaseService
from app.services.hero_generation import generate_hero
from app.schemas.hero import (
    HeroOut,
    HeroRead,
    HeroGenerateRequest,
    HeroStatsOut,
    SkillDetailOut,
    SkillCatalogOut,
    SkillEffectOut,
    HeroTagOut,
    BodyPartOut,
    HeroTitleOut,
    HeroHistoryOut,
    DerivedStatsOut,
)
from app.core.derived_stats import compute_derived_for_hero
from app.core.hero_config import MAX_HEROES
from app.core.events import emit
from sqlalchemy.orm import joinedload, selectinload


class HeroService(BaseService):

    # ── CRUD ──────────────────────────────────────────────────────

    async def get_hero(
        self,
        hero_id: int,
        only_active: bool = True,
        load_skills: bool = False,
        load_equipment: bool = False,
        load_body_parts: bool = False,
        load_titles: bool = False,
        load_history: bool = False,
        load_tags: bool = False,
    ):
        """Retrieve a hero, optionally eager-loading relationships."""
        query = select(Hero).where(Hero.id == hero_id)
        if load_skills:
            query = query.options(selectinload(Hero.skills))
        if load_equipment:
            from app.database.models.models import Equipment
            query = query.options(
                joinedload(Hero.equipment_items).joinedload(Equipment.item)
            )
        if load_body_parts:
            query = query.options(selectinload(Hero.body_parts))
        if load_titles:
            query = query.options(selectinload(Hero.titles))
        if load_history:
            query = query.options(selectinload(Hero.history_entries))
        if load_tags:
            query = query.options(selectinload(Hero.tags))
        result = await self.session.execute(query)
        return result.scalars().first()

    async def list_heroes(self, user_id: int = None, limit: int = 10, offset: int = 0):
        """List heroes with pagination support."""
        limit = max(1, min(limit, 100))
        offset = max(0, offset)

        count_query = select(func.count()).select_from(Hero)
        if user_id is not None:
            count_query = count_query.where(Hero.owner_id == user_id)
        total_result = await self.session.execute(count_query)
        total = total_result.scalars().first() or 0

        query = (
            select(Hero)
            .options(
                joinedload(Hero.stats),
                selectinload(Hero.skills),
                selectinload(Hero.tags),
                selectinload(Hero.body_parts),
                selectinload(Hero.titles),
            )
        )
        if user_id is not None:
            query = query.where(Hero.owner_id == user_id)
        query = query.limit(limit).offset(offset)
        result = await self.session.execute(query)
        items = result.unique().scalars().all()

        return {
            "items": items,
            "total": total,
            "limit": limit,
            "offset": offset,
        }

    async def update_hero(self, hero_id: int, name: str, user_id: int):
        hero = await self.get_hero(hero_id)
        if not hero or hero.owner_id != user_id:
            raise HTTPException(status_code=404, detail="Hero not found")
        hero.name = name
        await self.commit_or_rollback()
        await self.session.refresh(hero)
        await emit("cache_invalidate", f"heroes:{user_id}*")
        return hero

    async def delete_hero(self, hero_id: int, user_id: int):
        hero = await self.get_hero(hero_id, only_active=True)
        if not hero or hero.owner_id != user_id:
            raise HTTPException(status_code=404, detail="Hero not found or not yours")
        hero.is_deleted = True
        hero.deleted_at = datetime.utcnow()
        await self.commit_or_rollback()
        await emit("cache_invalidate", f"heroes:{user_id}*")
        return hero

    async def restore_hero(self, hero_id: int, user_id: int):
        hero = await self.get_hero(hero_id, only_active=False)
        if not hero or not hero.is_deleted or hero.owner_id != user_id:
            raise HTTPException(status_code=404, detail="Hero not found or not yours")
        cutoff = datetime.utcnow() - timedelta(days=7)
        if not hero.deleted_at or hero.deleted_at < cutoff:
            raise HTTPException(status_code=404, detail="Restore period expired")
        hero.is_deleted = False
        hero.deleted_at = None
        await self.commit_or_rollback()
        await emit("cache_invalidate", f"heroes:{user_id}*")
        return hero


    async def heal_hero(self, hero_id: int, user_id: int):
        """Restore hero to full HP and HEALTHY condition."""
        hero = await self.get_hero(hero_id, only_active=True)
        if not hero or hero.owner_id != user_id:
            raise HTTPException(status_code=404, detail="Hero not found")
        if hero.is_dead or hero.is_permadead:
            raise HTTPException(status_code=400, detail="Cannot heal a dead hero")
        derived = compute_derived_for_hero(hero)
        hero.current_hp = derived.max_hp
        hero.condition = HeroCondition.HEALTHY
        await self.commit_or_rollback()
        await self.session.refresh(hero)
        await emit("cache_invalidate", f"heroes:{user_id}*")
        return hero

    # ── Generation ───────────────────────────────────────────────

    async def generate_and_store(self, owner_id: int, req: HeroGenerateRequest):
        """Generate and store hero with atomic transaction.

        Locks the user row, checks hero limit, generates the hero,
        and commits atomically.
        """
        tx = self._txn()
        async with tx:
            # Lock user row to prevent concurrent hero creation
            user_result = await self.session.execute(
                select(User)
                .where(User.id == owner_id)
                .with_for_update()
            )
            user = user_result.scalars().first()
            if not user:
                raise HTTPException(404, "User not found")

            # Check hero limit
            res = await self.session.execute(
                select(func.count()).select_from(Hero)
                .where(Hero.owner_id == owner_id, Hero.is_deleted == False)
            )
            (count,) = res.one()
            if count >= MAX_HEROES:
                raise HTTPException(400, "Maximum heroes limit reached")

            # Generate hero (v2 engine)
            new_hero = await generate_hero(
                self.session,
                owner_id,
                locale=req.locale,
                seed=req.seed,
            )
            # Transaction auto-commits on success

        await self.session.refresh(new_hero)
        await emit("cache_invalidate", f"heroes:{owner_id}*")
        return new_hero

    # ── Read with relationships ──────────────────────────────────

    async def get_hero_full(self, hero_id: int) -> HeroRead:
        """Return a hero with all related data and derived stats."""
        hero = await self.get_hero(
            hero_id,
            load_skills=True,
            load_body_parts=True,
            load_titles=True,
            load_history=True,
            load_tags=True,
        )
        if not hero:
            raise HTTPException(status_code=404, detail="Hero not found")

        stats_out = None
        if hero.stats:
            stats_out = HeroStatsOut.model_validate(hero.stats, from_attributes=True)

        # ── Build rich skill output ──────────────────────────────
        skills_out: list[SkillDetailOut] = []
        for sk in (hero.skills or []):
            # Catalog metadata (joined via HeroSkill.catalog_entry)
            catalog_out = None
            if sk.catalog_entry:
                catalog_out = SkillCatalogOut.model_validate(
                    sk.catalog_entry, from_attributes=True,
                )

            # Normalised effects (selectin-loaded via HeroSkill.effects)
            effects_out = [
                SkillEffectOut.model_validate(eff, from_attributes=True)
                for eff in (sk.effects or [])
            ]

            skills_out.append(SkillDetailOut(
                id=sk.id,
                skill_code=sk.skill_code,
                slot_index=sk.slot_index,
                is_signature=sk.is_signature,
                source_type=sk.source_type.value if hasattr(sk.source_type, "value") else str(sk.source_type),
                generation_level=sk.generation_level,
                cost_generation_level=sk.cost_generation_level,
                power_value=sk.power_value,
                duration_value=sk.duration_value,
                cooldown_value=sk.cooldown_value,
                stamina_cost_value=sk.stamina_cost_value,
                radius_value=sk.radius_value,
                upgrade_count=sk.upgrade_count,
                payload_json=sk.payload_json,
                catalog=catalog_out,
                effects=effects_out,
            ))
        tags_out = [
            HeroTagOut.model_validate(t, from_attributes=True)
            for t in (hero.tags or [])
        ]
        body_parts_out = [
            BodyPartOut.model_validate(bp, from_attributes=True)
            for bp in (hero.body_parts or [])
        ]
        titles_out = [
            HeroTitleOut.model_validate(t, from_attributes=True)
            for t in (hero.titles or [])
        ]
        history_out = [
            HeroHistoryOut.model_validate(entry, from_attributes=True)
            for entry in (hero.history_entries or [])
        ]

        # Derived stats
        derived = compute_derived_for_hero(hero)
        derived_out = DerivedStatsOut(
            max_hp=derived.max_hp,
            initiative=derived.initiative,
            accuracy=derived.accuracy,
            evasion=derived.evasion,
            critical_chance=derived.critical_chance,
            critical_resistance=derived.critical_resistance,
            armor_efficiency=derived.armor_efficiency,
            recovery_speed=derived.recovery_speed,
            trauma_resistance=derived.trauma_resistance,
        )

        hero_dict = HeroOut.model_validate(hero, from_attributes=True).model_dump()
        hero_dict["stats"] = stats_out
        hero_dict["skills"] = skills_out
        hero_dict["tags"] = tags_out
        hero_dict["body_parts"] = body_parts_out
        hero_dict["titles"] = titles_out
        hero_dict["history"] = history_out
        hero_dict["derived_stats"] = derived_out
        return HeroRead(**hero_dict)

    async def get_total_stats(self, hero_id: int):
        """Return core stats + equipment bonuses + derived stats."""
        hero = await self.get_hero(hero_id, load_equipment=True)
        if not hero:
            raise HTTPException(status_code=404, detail="Hero not found")

        from app.core.generation_config import CORE_STATS

        base_stats = {}
        if hero.stats:
            base_stats = {stat: getattr(hero.stats, stat, 0) or 0 for stat in CORE_STATS}
        else:
            base_stats = {stat: 0 for stat in CORE_STATS}

        # Equipment bonuses
        equipment_bonuses: dict[str, int] = {}
        for eq in hero.equipment_items:
            item = eq.item
            for stat in CORE_STATS:
                bonus = getattr(item, f"bonus_{stat}", 0)
                if bonus:
                    equipment_bonuses[stat] = equipment_bonuses.get(stat, 0) + bonus
                    base_stats[stat] += bonus

        # Compute derived
        derived = compute_derived_for_hero(hero, equipment_bonuses)
        result = dict(base_stats)
        result["derived"] = {
            "max_hp": derived.max_hp,
            "initiative": derived.initiative,
            "accuracy": derived.accuracy,
            "evasion": derived.evasion,
            "critical_chance": derived.critical_chance,
            "critical_resistance": derived.critical_resistance,
            "armor_efficiency": derived.armor_efficiency,
            "recovery_speed": derived.recovery_speed,
            "trauma_resistance": derived.trauma_resistance,
        }
        return result

    async def send_offline_messages(self, user_id: int, websocket: str):
        from app.services.notification import NotificationService
        await NotificationService.send_offline_messages(user_id, websocket)
