# app/routers/announcement.py

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.schemas.announcement import AnnouncementCreate, AnnouncementOut
from app.services.announcement import AnnouncementService
from app.database.session import get_session
from app.auth import get_current_user, get_current_user_info

router = APIRouter(prefix="/announcements", tags=["Announcements"])


@router.post(
    "/",
    response_model=AnnouncementOut,
    summary="Create a new announcement",
    description="Creates a new announcement with the specified message. Only authenticated users can create announcements."
)
async def create_announcement(data: AnnouncementCreate, db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    service = AnnouncementService(db)
    ann = await service.create_announcement(message=data.message, author_id=current_user['user_id'])
    return AnnouncementOut.from_orm(ann)


@router.get(
    "/",
    response_model=List[AnnouncementOut],
    summary="List all announcements",
    description="Returns a list of all announcements in the system. Only authenticated users can view announcements."
)
async def read_announcements(db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    service = AnnouncementService(db)
    anns = await service.list_announcements()
    return [AnnouncementOut.from_orm(a) for a in anns]


@router.get(
    "/{announcement_id}",
    response_model=AnnouncementOut,
    summary="Get announcement by ID",
    description="Returns detailed information about a specific announcement by its ID. Only authenticated users can view announcements."
)
async def read_announcement(announcement_id: int, db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    service = AnnouncementService(db)
    ann = await service.get_announcement(announcement_id)
    if not ann:
        raise HTTPException(404, "Announcement not found")
    return AnnouncementOut.from_orm(ann)


@router.delete(
    "/{announcement_id}",
    response_model=AnnouncementOut,
    summary="Delete an announcement",
    description="Deletes an announcement by its ID. Only the author or an admin can delete announcements."
)
async def delete_announcement(announcement_id: int, db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    service = AnnouncementService(db)
    deleted = await service.delete_announcement(announcement_id)
    if not deleted:
        raise HTTPException(404, "Announcement not found")
    return AnnouncementOut.from_orm(deleted)
