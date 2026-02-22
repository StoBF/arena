from datetime import datetime, timedelta
from typing import List, Dict, Any
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.database.models.event import EventDefinition, EventInstance
from app.services.inventory import StashService

# Data-driven statuses via config
STATUS_UPCOMING = getattr(settings, "EVENT_STATUS_UPCOMING", "upcoming")
STATUS_ACTIVE   = getattr(settings, "EVENT_STATUS_ACTIVE",   "active")
STATUS_FINISHED = getattr(settings, "EVENT_STATUS_FINISHED", "finished")

class EventService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def schedule_events(self) -> List[int]:
        """
        Create new EventInstance rows for each EventDefinition that should fire now.
        Returns list of created instance IDs.
        """
        now = datetime.utcnow()
        results = await self.db.execute(EventDefinition.__table__.select())
        definitions: List[EventDefinition] = results.scalars().all()
        created: List[int] = []
        for d in definitions:
            # assume EventDefinition.has_cron_match is a model helper
            if d.has_cron_match(now):
                inst = EventInstance(
                    definition_id=d.id,
                    start_time=now,
                    end_time=now + timedelta(seconds=d.duration_sec),
                    status=STATUS_UPCOMING,
                    participants=[]
                )
                self.db.add(inst)
                await self.db.flush()
                created.append(inst.id)
        await self.db.commit()
        return created

    async def activate_event(self, instance_id: int) -> EventInstance:
        """
        Move an upcoming event instance into active state.
        """
        inst = await self.db.get(EventInstance, instance_id)
        if not inst:
            raise ValueError(f"EventInstance {instance_id} not found")
        if inst.status != STATUS_UPCOMING:
            raise ValueError(f"Cannot activate event in status {inst.status}")
        inst.status = STATUS_ACTIVE
        await self.db.commit()
        await self.db.refresh(inst)
        return inst

    async def finalize_event(self, instance_id: int) -> EventInstance:
        """
        Distribute rewards based on EventDefinition and mark the instance finished.
        """
        inst = await self.db.get(EventInstance, instance_id)
        if not inst:
            raise ValueError(f"EventInstance {instance_id} not found")
        if inst.status != STATUS_ACTIVE:
            raise ValueError(f"Cannot finalize event in status {inst.status}")
        # Allocate rewards to each participant
        ev_def = await self.db.get(EventDefinition, inst.definition_id)
        stash_service = StashService(self.db)
        for user_id in inst.participants:
            for reward in ev_def.rewards:
                await stash_service.add_to_stash(
                    user_id,
                    reward["id"],
                    reward.get("qty", 1)
                )
        inst.status = STATUS_FINISHED
        inst.completed_at = datetime.utcnow()
        await self.db.commit()
        await self.db.refresh(inst)
        return inst

    async def join_event(self, user_id: int, instance_id: int) -> EventInstance:
        """
        Add a user to an active event instance.
        """
        inst = await self.db.get(EventInstance, instance_id)
        if not inst:
            raise ValueError(f"EventInstance {instance_id} not found")
        if inst.status != STATUS_ACTIVE:
            raise ValueError(f"Cannot join event in status {inst.status}")
        if user_id not in inst.participants:
            inst.participants.append(user_id)
            await self.db.commit()
            await self.db.refresh(inst)
        return inst 