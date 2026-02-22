# app/routers/events.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.services.events import EventService
from app.schemas.events import EventDefinitionOut, EventInstanceOut, EventJoinIn
from app.database.models.event import EventDefinition
from app.database.session import get_session
from app.auth import get_current_user_info

router = APIRouter(prefix="/events", tags=["Events"])

@router.get("/definitions", response_model=List[EventDefinitionOut])
async def list_definitions(db: AsyncSession = Depends(get_session)):
    """List all event definitions with schedule and rewards"""
    result = await db.execute(EventDefinition.__table__.select())
    return result.scalars().all()

@router.post("/schedule", response_model=List[int])
async def schedule_events(db: AsyncSession = Depends(get_session)):
    """Run scheduler to create new upcoming event instances"""
    return await EventService(db).schedule_events()

@router.post("/{instance_id}/activate", response_model=EventInstanceOut)
async def activate_event(
    instance_id: int,
    db: AsyncSession = Depends(get_session)
):
    """Activate an upcoming event"""
    try:
        return await EventService(db).activate_event(instance_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/{instance_id}/finalize", response_model=EventInstanceOut)
async def finalize_event(
    instance_id: int,
    db: AsyncSession = Depends(get_session)
):
    """Finalize an active event and distribute rewards"""
    try:
        return await EventService(db).finalize_event(instance_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/{instance_id}/join", response_model=EventInstanceOut)
async def join_event(
    instance_id: int,
    payload: EventJoinIn,
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    """Join the given active event instance"""
    try:
        return await EventService(db).join_event(current_user["user_id"], instance_id)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e)) 