# app/routers/pvp.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.schemas.pvp import PvPMatchIn, PvPBattleLogOut, LeaderboardEntryOut
from app.services.pvp import PvpService
from app.database.models.models import LeaderboardEntry
from app.database.session import get_session

router = APIRouter(prefix="/pvp", tags=["PvP"])

@router.post("/match", response_model=PvPBattleLogOut)
async def create_match(
    payload: PvPMatchIn,
    db: AsyncSession = Depends(get_session)
):
    """Create and run a PvP match between two players."""
    service = PvpService(db)
    match = await service.create_match(payload.player1_id, payload.player2_id)
    try:
        return await service.run_match(match.id)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/leaderboard", response_model=List[LeaderboardEntryOut])
async def get_leaderboard(
    db: AsyncSession = Depends(get_session)
):
    """Fetch top 100 players by rating."""
    stmt = LeaderboardEntry.__table__.select().order_by(LeaderboardEntry.rating.desc()).limit(100)
    result = await db.execute(stmt)
    return result.scalars().all() 