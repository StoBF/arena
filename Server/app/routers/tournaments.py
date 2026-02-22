# app/routers/tournaments.py
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.services.tournaments import TournamentService
from app.schemas.tournaments import TournamentCreateIn, TournamentOut, MatchAdvanceIn
from app.database.session import get_session
from app.auth import get_current_user_info

router = APIRouter(prefix="/tournaments", tags=["Tournaments"])

@router.post("", response_model=TournamentOut)
async def launch_tournament(
    payload: TournamentCreateIn,
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    """Create a new tournament instance based on a template and participants."""
    try:
        return await TournamentService(db).create_tournament(payload.template_id, payload.user_ids)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/{tournament_id}/advance", response_model=TournamentOut)
async def advance_tournament(
    tournament_id: int,
    payload: MatchAdvanceIn,
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    """Advance a specific match in the tournament bracket."""
    try:
        return await TournamentService(db).advance_match(
            tournament_id,
            payload.round_no,
            payload.match_no,
            payload.winner_id
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e)) 