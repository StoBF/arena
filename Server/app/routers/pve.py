from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.services.raid import RaidService
from app.schemas.raid import ArenaInstanceOut, PvEBattleLogOut, RewardOut
from app.database.session import get_session
from app.auth import get_current_user_info

router = APIRouter(prefix="/pve/raid", tags=["PvE"])

@router.post("/start", response_model=ArenaInstanceOut)
async def start_raid(
    hero_ids: List[int],
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info)
):
    """Start a new PvE raid instance based on user's heroes."""
    try:
        return await RaidService(db).start_instance(
            boss_id=user.get("boss_id", 0),  # pass boss_id externally or via payload
            user_id=user["user_id"],
            hero_ids=hero_ids
        )
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/battle/{instance_id}", response_model=PvEBattleLogOut)
async def battle(
    instance_id: int,
    db: AsyncSession = Depends(get_session)
):
    """Execute the battle simulation for a PvE raid instance."""
    return await RaidService(db).run_pve_battle(instance_id)

@router.post("/rewards/{instance_id}", response_model=List[RewardOut])
async def rewards(
    instance_id: int,
    db: AsyncSession = Depends(get_session)
):
    """Roll and fetch rewards for a completed PvE raid instance."""
    return await RaidService(db).drop_rewards(instance_id) 