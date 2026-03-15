# app/services/training.py

import math
import json
from datetime import datetime, timedelta
from sqlalchemy.future import select
from sqlalchemy import func
from fastapi import HTTPException

from app.services.base_service import BaseService
from app.database.models.hero import (
    Hero, HeroTrainingQueue, HeroHistory, HeroAbility,
    TrainingType, TrainingStatus,
)
from app.schemas.hero import TrainingStartRequest, TrainingQueueOut, TrainingQueueResponse
from app.core.hero_config import (
    PRIMARY_STATS, TRAINING_BASE_TIME, TRAINING_MAX_QUEUE_SLOTS, DISCIPLINES,
)
from app.core.events import emit


# ---------------------------------------------------------------------------
# Time formula: base_time * (1 + level * 0.18) ^ 1.35
# ---------------------------------------------------------------------------

def compute_training_minutes(training_type: str, current_level: int, efficiency: float = 1.0) -> float:
    """Return training duration in minutes for one level-up."""
    base = TRAINING_BASE_TIME.get(training_type, 30)
    raw = base * ((1 + current_level * 0.18) ** 1.35)
    return max(1.0, raw / efficiency)


# ---------------------------------------------------------------------------
# Validation helpers
# ---------------------------------------------------------------------------

def _validate_target(training_type: TrainingType, target: str) -> None:
    if training_type == TrainingType.ATTRIBUTE:
        if target not in PRIMARY_STATS:
            raise HTTPException(400, f"Invalid attribute target. Must be one of: {PRIMARY_STATS}")
    elif training_type == TrainingType.DISCIPLINE:
        if target not in DISCIPLINES:
            valid = list(DISCIPLINES.keys())
            raise HTTPException(400, f"Unknown discipline '{target}'. Valid: {valid}")
    elif training_type == TrainingType.ABILITY:
        # Ability codes are free-form; validated against hero's actual abilities later
        if not target:
            raise HTTPException(400, "ability training_target cannot be empty")


def _enrich_queue_out(entry: HeroTrainingQueue) -> TrainingQueueOut:
    """Convert DB row to response schema with live time_remaining."""
    out = TrainingQueueOut.model_validate(entry, from_attributes=True)
    if entry.status == TrainingStatus.RUNNING and entry.ends_at:
        remaining = (entry.ends_at - datetime.utcnow()).total_seconds()
        out.time_remaining_seconds = max(0, int(remaining))
    else:
        out.time_remaining_seconds = None
    return out


# ---------------------------------------------------------------------------
# Service
# ---------------------------------------------------------------------------

class TrainingService(BaseService):

    # ── helpers ───────────────────────────────────────────────────────────

    async def _get_owned_hero(self, hero_id: int, owner_id: int) -> Hero:
        hero = await self.session.get(Hero, hero_id)
        if not hero or hero.owner_id != owner_id or hero.is_deleted:
            raise HTTPException(404, "Hero not found")
        if hero.is_dead or hero.is_permadead:
            raise HTTPException(400, "Dead heroes cannot train")
        return hero

    async def _active_count(self, hero_id: int) -> int:
        res = await self.session.execute(
            select(func.count()).select_from(HeroTrainingQueue).where(
                HeroTrainingQueue.hero_id == hero_id,
                HeroTrainingQueue.status.in_([TrainingStatus.QUEUED, TrainingStatus.RUNNING]),
            )
        )
        return res.scalar() or 0

    async def _slot_occupied(self, hero_id: int, slot: int) -> bool:
        res = await self.session.execute(
            select(func.count()).select_from(HeroTrainingQueue).where(
                HeroTrainingQueue.hero_id == hero_id,
                HeroTrainingQueue.room_slot == slot,
                HeroTrainingQueue.status.in_([TrainingStatus.QUEUED, TrainingStatus.RUNNING]),
            )
        )
        return (res.scalar() or 0) > 0

    async def _current_target_level(self, hero: Hero, training_type: TrainingType, target: str) -> int:
        """Determine the current level of a training target on the hero."""
        if training_type == TrainingType.ATTRIBUTE:
            return getattr(hero, target, 0) or 0
        elif training_type == TrainingType.DISCIPLINE:
            # Discipline levels live in the queue history; count completions
            res = await self.session.execute(
                select(func.count()).select_from(HeroTrainingQueue).where(
                    HeroTrainingQueue.hero_id == hero.id,
                    HeroTrainingQueue.training_type == TrainingType.DISCIPLINE,
                    HeroTrainingQueue.training_target == target,
                    HeroTrainingQueue.status == TrainingStatus.COMPLETED,
                )
            )
            return res.scalar() or 0
        elif training_type == TrainingType.ABILITY:
            res = await self.session.execute(
                select(HeroAbility.ability_level).where(
                    HeroAbility.hero_id == hero.id,
                    HeroAbility.ability_code == target,
                )
            )
            row = res.scalar()
            return row if row else 0
        return 0

    # ── start ─────────────────────────────────────────────────────────────

    async def start_training(
        self, hero_id: int, owner_id: int, req: TrainingStartRequest,
    ) -> TrainingQueueOut:
        hero = await self._get_owned_hero(hero_id, owner_id)

        _validate_target(req.training_type, req.training_target)

        # Ability training requires hero to own the ability
        if req.training_type == TrainingType.ABILITY:
            res = await self.session.execute(
                select(HeroAbility).where(
                    HeroAbility.hero_id == hero.id,
                    HeroAbility.ability_code == req.training_target,
                )
            )
            if not res.scalars().first():
                raise HTTPException(400, f"Hero does not have ability '{req.training_target}'")

        # Slot capacity
        active = await self._active_count(hero_id)
        if active >= TRAINING_MAX_QUEUE_SLOTS:
            raise HTTPException(400, f"Training queue full ({TRAINING_MAX_QUEUE_SLOTS} slots max)")

        if await self._slot_occupied(hero_id, req.room_slot):
            raise HTTPException(400, f"Room slot {req.room_slot} is already in use")

        current_level = await self._current_target_level(hero, req.training_type, req.training_target)

        if req.target_level <= current_level:
            raise HTTPException(400, f"Target level {req.target_level} must be higher than current level {current_level}")

        duration = compute_training_minutes(req.training_type.value, current_level)
        now = datetime.utcnow()

        entry = HeroTrainingQueue(
            hero_id=hero.id,
            training_type=req.training_type,
            training_target=req.training_target,
            current_level=current_level,
            target_level=req.target_level,
            started_at=now,
            ends_at=now + timedelta(minutes=duration),
            status=TrainingStatus.RUNNING,
            room_slot=req.room_slot,
            efficiency=1.0,
        )
        self.session.add(entry)

        self.session.add(HeroHistory(
            hero_id=hero.id,
            event_type="training_queued",
            event_data=json.dumps({
                "training_type": req.training_type.value,
                "target": req.training_target,
                "from_level": current_level,
                "to_level": req.target_level,
                "duration_minutes": round(duration, 1),
                "room_slot": req.room_slot,
            }),
        ))

        await self.commit_or_rollback()
        await self.session.refresh(entry)
        await emit("cache_invalidate", f"heroes:{hero.owner_id}*")
        return _enrich_queue_out(entry)

    # ── cancel ────────────────────────────────────────────────────────────

    async def cancel_training(
        self, hero_id: int, owner_id: int, entry_id: int | None = None,
    ) -> TrainingQueueOut:
        hero = await self._get_owned_hero(hero_id, owner_id)

        query = select(HeroTrainingQueue).where(
            HeroTrainingQueue.hero_id == hero.id,
            HeroTrainingQueue.status.in_([TrainingStatus.QUEUED, TrainingStatus.RUNNING]),
        )
        if entry_id is not None:
            query = query.where(HeroTrainingQueue.id == entry_id)
        else:
            query = query.order_by(HeroTrainingQueue.started_at.desc()).limit(1)

        res = await self.session.execute(query)
        entry = res.scalars().first()
        if not entry:
            raise HTTPException(404, "No active training entry found")

        entry.status = TrainingStatus.CANCELLED

        self.session.add(HeroHistory(
            hero_id=hero.id,
            event_type="training_cancelled",
            event_data=json.dumps({
                "entry_id": entry.id,
                "training_type": entry.training_type.value,
                "target": entry.training_target,
            }),
        ))

        await self.commit_or_rollback()
        await self.session.refresh(entry)
        await emit("cache_invalidate", f"heroes:{hero.owner_id}*")
        return _enrich_queue_out(entry)

    # ── claim ─────────────────────────────────────────────────────────────

    async def claim_training(
        self, hero_id: int, owner_id: int, entry_id: int | None = None,
    ) -> TrainingQueueOut:
        hero = await self._get_owned_hero(hero_id, owner_id)

        query = select(HeroTrainingQueue).where(
            HeroTrainingQueue.hero_id == hero.id,
            HeroTrainingQueue.status == TrainingStatus.RUNNING,
        )
        if entry_id is not None:
            query = query.where(HeroTrainingQueue.id == entry_id)
        else:
            query = query.order_by(HeroTrainingQueue.started_at.asc()).limit(1)

        res = await self.session.execute(query)
        entry = res.scalars().first()
        if not entry:
            raise HTTPException(404, "No running training entry found")

        if entry.ends_at and entry.ends_at > datetime.utcnow():
            raise HTTPException(400, "Training not finished yet")

        # --- Apply training result ---
        entry.status = TrainingStatus.COMPLETED
        one_level = entry.current_level + 1  # award one level per claim

        if entry.training_type == TrainingType.ATTRIBUTE:
            current_val = getattr(hero, entry.training_target, 0) or 0
            setattr(hero, entry.training_target, current_val + 1)
            hero.training_sessions_completed = (hero.training_sessions_completed or 0) + 1

        elif entry.training_type == TrainingType.ABILITY:
            ab_res = await self.session.execute(
                select(HeroAbility).where(
                    HeroAbility.hero_id == hero.id,
                    HeroAbility.ability_code == entry.training_target,
                )
            )
            ability = ab_res.scalars().first()
            if ability:
                ability.ability_level += 1

        # discipline: no model field to bump; the completed-entry count itself is the level

        # If there are more levels to go, re-queue automatically
        if one_level < entry.target_level:
            next_duration = compute_training_minutes(
                entry.training_type.value, one_level, entry.efficiency,
            )
            now = datetime.utcnow()
            next_entry = HeroTrainingQueue(
                hero_id=hero.id,
                training_type=entry.training_type,
                training_target=entry.training_target,
                current_level=one_level,
                target_level=entry.target_level,
                started_at=now,
                ends_at=now + timedelta(minutes=next_duration),
                status=TrainingStatus.RUNNING,
                room_slot=entry.room_slot,
                efficiency=entry.efficiency,
            )
            self.session.add(next_entry)

        self.session.add(HeroHistory(
            hero_id=hero.id,
            event_type="training_claimed",
            event_data=json.dumps({
                "entry_id": entry.id,
                "training_type": entry.training_type.value,
                "target": entry.training_target,
                "level_reached": one_level,
                "target_level": entry.target_level,
                "continuing": one_level < entry.target_level,
            }),
        ))

        await self.commit_or_rollback()
        await self.session.refresh(entry)
        await emit("cache_invalidate", f"heroes:{hero.owner_id}*")
        return _enrich_queue_out(entry)

    # ── list ──────────────────────────────────────────────────────────────

    async def get_training_queue(self, hero_id: int, owner_id: int) -> TrainingQueueResponse:
        hero = await self._get_owned_hero(hero_id, owner_id)

        res = await self.session.execute(
            select(HeroTrainingQueue)
            .where(
                HeroTrainingQueue.hero_id == hero.id,
                HeroTrainingQueue.status.in_([TrainingStatus.QUEUED, TrainingStatus.RUNNING, TrainingStatus.COMPLETED]),
            )
            .order_by(HeroTrainingQueue.room_slot, HeroTrainingQueue.started_at.desc())
        )
        entries = res.scalars().all()
        return TrainingQueueResponse(
            hero_id=hero.id,
            slots=[_enrich_queue_out(e) for e in entries],
        )
