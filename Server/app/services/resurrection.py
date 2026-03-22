# app/services/resurrection.py

import json
import random
from datetime import datetime
from sqlalchemy.future import select
from fastapi import HTTPException

from app.services.base_service import BaseService
from app.database.models.hero import (
    Hero, HeroResurrectionEvent, HeroHistory, HeroCondition,
)
from app.schemas.hero import ResurrectionEventOut, HeroStatusResponse
from app.core.hero_config import (
    RESURRECTION_ARTIFACTS, MAX_RESURRECTIONS, CONDITION_THRESHOLDS,
)
from app.core.generation_config import CORE_STATS
from app.core.derived_stats import compute_derived_for_hero
from app.core.events import emit


# ---------------------------------------------------------------------------
# Condition helpers
# ---------------------------------------------------------------------------

def condition_from_hp(current_hp: int, max_hp: int) -> HeroCondition:
    """Derive HeroCondition from the HP ratio."""
    if max_hp <= 0 or current_hp <= 0:
        return HeroCondition.DEAD
    ratio = current_hp / max_hp
    for threshold, cond_name in CONDITION_THRESHOLDS:
        if ratio >= threshold:
            return HeroCondition(cond_name)
    return HeroCondition.DEAD


def update_hero_condition(hero: Hero, max_hp: int | None = None) -> None:
    """Recalculate and set a hero's condition based on current HP."""
    if max_hp is None:
        derived = compute_derived_for_hero(hero)
        max_hp = derived.max_hp
    hero.condition = condition_from_hp(hero.current_hp, max_hp)
    if hero.condition == HeroCondition.DEAD and not hero.is_dead:
        hero.is_dead = True
        hero.dead_at = datetime.utcnow()


# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------

class ResurrectionService(BaseService):

    async def _get_owned_hero(self, hero_id: int, owner_id: int) -> Hero:
        hero = await self.session.get(Hero, hero_id)
        if not hero or hero.owner_id != owner_id or hero.is_deleted:
            raise HTTPException(404, "Hero not found")
        return hero

    # ── resurrect ─────────────────────────────────────────────────────────

    async def resurrect(
        self, hero_id: int, owner_id: int, artifact_code: str,
    ) -> ResurrectionEventOut:
        hero = await self._get_owned_hero(hero_id, owner_id)

        # Must be dead
        if not hero.is_dead:
            raise HTTPException(400, "Hero is not dead")

        # Permadeath check
        if hero.is_permadead:
            raise HTTPException(400, "Hero has suffered permanent death and cannot be revived")

        # Resurrection cap
        if hero.resurrection_count >= MAX_RESURRECTIONS:
            hero.is_permadead = True
            await self.commit_or_rollback()
            raise HTTPException(
                400,
                f"Hero has been revived {MAX_RESURRECTIONS} times and is now permanently dead",
            )

        # Validate artifact
        artifact = RESURRECTION_ARTIFACTS.get(artifact_code)
        if not artifact:
            valid = list(RESURRECTION_ARTIFACTS.keys())
            raise HTTPException(400, f"Unknown artifact '{artifact_code}'. Valid: {valid}")

        # TODO: in future, check player inventory for the artifact item and consume it.

        # Compute restoration
        derived = compute_derived_for_hero(hero)
        max_hp = derived.max_hp
        restored_hp = max(1, int(max_hp * artifact["hp_restore_pct"]))

        condition_before = hero.condition
        condition_after = HeroCondition(artifact["condition_after"])

        # --- Apply side effects ---
        applied_effects = []
        for effect in artifact.get("side_effects", []):
            effect_entry = {"type": effect["type"], "desc": effect["desc"]}

            if effect["type"] == "stat_reduction" and hero.stats:
                penalty = effect.get("stat_penalty", 1)
                stat = random.choice(CORE_STATS)
                current_val = getattr(hero.stats, stat, 0) or 0
                new_val = max(1, current_val - penalty)
                setattr(hero.stats, stat, new_val)
                effect_entry["stat"] = stat
                effect_entry["old_value"] = current_val
                effect_entry["new_value"] = new_val

            applied_effects.append(effect_entry)

        # --- Revive hero ---
        hero.current_hp = restored_hp
        hero.is_dead = False
        hero.dead_at = None
        hero.death_cause = None
        hero.condition = condition_after
        hero.resurrection_count = (hero.resurrection_count or 0) + 1
        hero.total_deaths = (hero.total_deaths or 0)  # keep count, don't reset

        # --- Log resurrection event ---
        event = HeroResurrectionEvent(
            hero_id=hero.id,
            artifact_used=artifact_code,
            side_effects_json=json.dumps(applied_effects) if applied_effects else None,
            condition_before=condition_before,
            condition_after=condition_after,
            hp_restored_to=restored_hp,
        )
        self.session.add(event)

        # --- History entry ---
        self.session.add(HeroHistory(
            hero_id=hero.id,
            event_type="resurrected",
            event_data=json.dumps({
                "artifact": artifact_code,
                "hp_restored_to": restored_hp,
                "condition_after": condition_after.value,
                "side_effects": applied_effects,
                "resurrection_number": hero.resurrection_count,
            }),
        ))

        await self.commit_or_rollback()
        await self.session.refresh(event)
        await emit("cache_invalidate", f"heroes:{hero.owner_id}*")
        return ResurrectionEventOut.model_validate(event, from_attributes=True)

    # ── kill hero (for use by combat systems) ─────────────────────────────

    async def kill_hero(
        self, hero_id: int, death_cause: str = "unknown",
    ) -> Hero:
        """Mark a hero as dead. Called by combat/arena systems."""
        hero = await self.session.get(Hero, hero_id)
        if not hero:
            raise HTTPException(404, "Hero not found")
        if hero.is_dead:
            return hero  # already dead

        hero.current_hp = 0
        hero.is_dead = True
        hero.dead_at = datetime.utcnow()
        hero.death_cause = death_cause
        hero.condition = HeroCondition.DEAD
        hero.total_deaths = (hero.total_deaths or 0) + 1

        self.session.add(HeroHistory(
            hero_id=hero.id,
            event_type="died",
            event_data=json.dumps({
                "cause": death_cause,
                "total_deaths": hero.total_deaths,
            }),
        ))

        await self.commit_or_rollback()
        await self.session.refresh(hero)
        await emit("cache_invalidate", f"heroes:{hero.owner_id}*")
        return hero

    # ── wound hero (adjust condition from combat damage) ──────────────────

    async def apply_damage(
        self, hero_id: int, damage: int,
    ) -> HeroStatusResponse:
        """Reduce HP and update condition. Returns new status."""
        hero = await self.session.get(Hero, hero_id)
        if not hero:
            raise HTTPException(404, "Hero not found")
        if hero.is_dead:
            raise HTTPException(400, "Hero is already dead")

        derived = compute_derived_for_hero(hero)
        hero.current_hp = max(0, hero.current_hp - damage)
        update_hero_condition(hero, derived.max_hp)

        if hero.condition == HeroCondition.DEAD:
            hero.death_cause = "combat_damage"
            hero.total_deaths = (hero.total_deaths or 0) + 1
            self.session.add(HeroHistory(
                hero_id=hero.id,
                event_type="died",
                event_data=json.dumps({"cause": "combat_damage", "damage": damage}),
            ))

        await self.commit_or_rollback()
        await self.session.refresh(hero)
        await emit("cache_invalidate", f"heroes:{hero.owner_id}*")

        return HeroStatusResponse(
            hero_id=hero.id,
            name=hero.name,
            condition=hero.condition,
            is_dead=hero.is_dead,
            is_permadead=hero.is_permadead,
            current_hp=hero.current_hp,
            resurrection_count=hero.resurrection_count or 0,
            death_cause=hero.death_cause,
            dead_at=hero.dead_at,
        )

    # ── get status ────────────────────────────────────────────────────────

    async def get_status(self, hero_id: int, owner_id: int) -> HeroStatusResponse:
        hero = await self._get_owned_hero(hero_id, owner_id)
        return HeroStatusResponse(
            hero_id=hero.id,
            name=hero.name,
            condition=hero.condition,
            is_dead=hero.is_dead,
            is_permadead=hero.is_permadead,
            current_hp=hero.current_hp,
            resurrection_count=hero.resurrection_count or 0,
            death_cause=hero.death_cause,
            dead_at=hero.dead_at,
        )
