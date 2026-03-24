from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.services.raid import RaidService
from app.services.reward_distributor import RewardDistributor
from app.schemas.raid import RaidBossOut, ArenaInstanceOut, PvEBattleLogOut, RewardOut, RaidStartIn
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
    payload: RaidStartIn,
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    """Create a new raid instance"""
    user_id = current_user["user_id"]
    try:
        return await RaidService(db).start_instance(payload.boss_id, user_id, payload.hero_ids)
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.post("/battle/{instance_id}", response_model=PvEBattleLogOut)
async def battle_raid(
    instance_id: int,
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    """Execute the PvE battle for an existing raid instance"""
    return await RaidService(db).run_pve_battle(instance_id)

@router.post("/rewards/{instance_id}", response_model=List[RewardOut])
async def raid_rewards(
    instance_id: int,
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    """Roll and fetch rewards for a completed raid instance.
    Distributes currency + resources via RewardDistributor (with ticket drops)
    and also runs the legacy item-drop logic from RaidService.
    """
    service  = RaidService(db)
    instance = await service._get_instance(instance_id)
    if instance is None:
        raise HTTPException(404, "Instance not found")

    # Legacy item drops (recipes, equipment from loot tables)
    item_rewards = await service.drop_rewards(instance_id)

    # Currency + resources + raid ticket via RewardDistributor
    boss = await db.get(RaidBoss, instance.boss_id)
    boss_tier = getattr(boss, "tier", 1) if boss else 1
    success   = getattr(instance, "result", None) in ("victory", "win", None)
    user_ids  = getattr(instance, "participant_user_ids", [current_user["user_id"]])

    dist = RewardDistributor(db)
    currency_rewards = await dist.distribute_raid(
        user_ids  = user_ids if isinstance(user_ids, list) else [user_ids],
        boss_tier = boss_tier,
        success   = success,
    )

    # Merge currency info into response payload
    for r in item_rewards:
        uid = getattr(r, "user_id", None) or current_user["user_id"]
        if uid in currency_rewards:
            r_dict = currency_rewards[uid]
            # Attach currency/resource summary as extra field if schema allows
            if hasattr(r, "__dict__"):
                r.__dict__["currency_awarded"] = r_dict.get("currency", 0)

    return item_rewards
