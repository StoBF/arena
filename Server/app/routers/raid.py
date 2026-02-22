from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.services.raid import RaidService
from app.schemas.raid import RaidBossOut, ArenaInstanceOut, PvEBattleLogOut, RewardOut
from app.database.models.raid_boss import RaidBoss
from app.database.session import get_session
from app.auth import get_current_user_info

router = APIRouter(prefix="/raid", tags=["Raid"])

@router.get("/bosses", response_model=List[RaidBossOut])
async def list_raid_bosses(
    db: AsyncSession = Depends(get_session)
):
    """List all raid bosses"""
    result = await db.execute(RaidBoss.__table__.select())
    return result.scalars().all()

@router.post("/start", response_model=ArenaInstanceOut)
async def start_raid(
    boss_id: int,
    hero_ids: List[int],
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    """Create a new raid instance"""
    user_id = current_user["user_id"]
    try:
        return await RaidService(db).start_instance(boss_id, user_id, hero_ids)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/battle/{instance_id}", response_model=PvEBattleLogOut)
async def battle_raid(
    instance_id: int,
    db: AsyncSession = Depends(get_session)
):
    """Execute the PvE battle for an existing raid instance"""
    return await RaidService(db).run_pve_battle(instance_id)

@router.post("/rewards/{instance_id}", response_model=List[RewardOut])
async def raid_rewards(
    instance_id: int,
    db: AsyncSession = Depends(get_session)
):
    """Roll and fetch rewards for a completed raid instance"""
    return await RaidService(db).drop_rewards(instance_id)

# TODO: /raid/reward/{raid_id} — видача нагороди після перемоги 