# app/routers/pvp.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.schemas.pvp import PvPMatchIn, PvPBattleLogOut, LeaderboardEntryOut
from app.services.pvp import PvpService
from app.services.reward_distributor import RewardDistributor
from app.database.models.models import LeaderboardEntry
from app.database.session import get_session
from app.auth import get_current_user_info

router = APIRouter(prefix="/pvp", tags=["PvP"])

@router.post("/match", response_model=PvPBattleLogOut)
async def create_match(
    payload: PvPMatchIn,
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info),
):
    """Create and run a PvP match between two players, then distribute rewards."""
    service = PvpService(db)
    match   = await service.create_match(payload.player1_id, payload.player2_id)
    try:
        log = await service.run_match(match.id)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

    # Distribute currency + resources to both players
    winner = getattr(log, "winner", None) or getattr(match, "winner", None)
    winner_str = "a" if str(winner) == str(payload.player1_id) else (
                 "b" if str(winner) == str(payload.player2_id) else "draw")
    try:
        dist = RewardDistributor(db)
        await dist.distribute_pvp(
            winner_team = winner_str,
            team_a_ids  = [payload.player1_id],
            team_b_ids  = [payload.player2_id],
        )
    except Exception:
        pass  # reward failure must not break the match response

    return log

@router.get("/leaderboard", response_model=List[LeaderboardEntryOut])
async def get_leaderboard(
    db: AsyncSession = Depends(get_session),
):
    """Fetch top 100 players by rating."""
    stmt = LeaderboardEntry.__table__.select().order_by(LeaderboardEntry.rating.desc()).limit(100)
    result = await db.execute(stmt)
    return result.scalars().all()
