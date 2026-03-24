"""
Raid Boss Router — 14 endpoints.

Endpoints
---------
GET  /raid-bosses/                  — list active spawns
GET  /raid-bosses/calendar          — upcoming spawn schedule
GET  /raid-bosses/{template_id}     — boss details + phases
GET  /raid-bosses/{template_id}/loot — full loot table with chances
GET  /raid-bosses/{template_id}/history — boss battle history

POST /raid-rooms/create             — create raid room for a spawn
POST /raid-rooms/{room_id}/join     — join room with a hero
POST /raid-rooms/{room_id}/ready    — mark hero as ready
POST /raid-rooms/{room_id}/lock     — lock roster
POST /raid-rooms/{room_id}/start    — start raid simulation
GET  /raid-rooms/{room_id}          — room details + participants
GET  /raid-rooms/{room_id}/result   — battle result + reward rolls

POST /raid-coalitions/create        — create coalition for a spawn
POST /raid-coalitions/{id}/invite   — invite clan
POST /raid-coalitions/{id}/accept   — accept invite

GET  /raid-access/ranking           — clan RAP ranking
GET  /raid-access/my-score          — current user's clan score
POST /raid-access/add               — add RAP (internal/admin)

POST /raid-bosses/seed              — seed boss templates (admin)
"""
from __future__ import annotations

from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.session import get_session
from app.auth import get_current_user_info
from app.database.models.raid_v2 import (
    RaidBossTemplate, RaidBossSpawn, RaidBossProgress, RaidBossPhase,
    RaidBossMutation, RaidBossHistory, RaidRoom, RaidParticipant,
    RaidCoalition, RaidCoalitionClan, RaidAccessScore,
    RaidBattleLog, RaidContribution, RaidRewardRoll,
    SpawnStatus,
)
from app.services.raid_boss import (
    SpawnService, AccessService, RoomService,
    RaidBattleService, RaidRewardService,
)

router = APIRouter(prefix="/raid-bosses", tags=["raid-boss"])
rooms_router = APIRouter(prefix="/raid-rooms", tags=["raid-rooms"])
coalition_router = APIRouter(prefix="/raid-coalitions", tags=["raid-coalitions"])
access_router = APIRouter(prefix="/raid-access", tags=["raid-access"])


# ═══════════════════════════════════════════════════════════════════════════════
# Schemas
# ═══════════════════════════════════════════════════════════════════════════════

class PhaseOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    phase_number:   int
    trigger_hp_pct: float
    name:           str
    description:    Optional[str]
    modifiers:      Dict
    abilities:      List[str]
    arena_changes:  Dict


class MutationOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    code:        str
    name:        str
    description: Optional[str]
    effect:      Dict
    is_active:   bool


class ProgressOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    current_level:   int
    rank:            int
    evolution_stage: int
    win_streak:      int
    total_wins:      int
    total_defeats:   int
    hero_kills:      int


class BossDetailOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id:            int
    code:          str
    name:          str
    category:      str
    archetype:     str
    max_clans:     int
    max_heroes:    int
    num_phases:    int
    base_level:    int
    description:   Optional[str]
    lore:          Optional[str]
    spawn_config:  Dict
    requires_qualification: bool
    min_access_points: int


class SpawnOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id:           int
    template_id:  int
    status:       str
    opens_at:     Any
    closes_at:    Any
    boss_level_snapshot: int
    win_streak_snapshot: int


class LootEntryOut(BaseModel):
    display_name:     str
    rarity:           str
    ownership:        str
    drop_group:       str
    base_chance:      float
    adjusted_chance:  float
    min_qty:          int
    max_qty:          int
    is_guaranteed:    bool
    bonus_conditions: List[Dict]
    item_code:        Optional[str]
    recipe_code:      Optional[str]
    artifact_code:    Optional[str]


class HistoryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    outcome:        str
    clan_names:     List[str]
    hero_count:     int
    xp_gained:      int
    level_before:   int
    level_after:    int
    mutation_gained: Optional[str]
    occurred_at:    Any


class CreateRoomIn(BaseModel):
    spawn_id:   int
    loot_rule:  str = "contribution"
    clan_id:    Optional[int] = None


class JoinRoomIn(BaseModel):
    user_id: int
    hero_id: int
    clan_id: Optional[int] = None


class ParticipantOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id:        int
    user_id:   int
    hero_id:   int
    clan_id:   Optional[int]
    is_ready:  bool


class RoomOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id:        int
    spawn_id:  int
    status:    str
    loot_rule: str
    created_at: Any


class BattleResultOut(BaseModel):
    outcome:               str
    total_ticks:           int
    phases_broken:         int
    boss_hp_remaining_pct: float
    boss_xp_gained:        int
    level_before:          int
    level_after:           int
    mutation_gained:       Optional[str]
    summary:               Dict
    contributions:         List[Dict]


class CreateCoalitionIn(BaseModel):
    spawn_id:      int
    leader_clan_id: int
    loot_rule:     str = "contribution"
    name:          Optional[str] = None


class InviteClanIn(BaseModel):
    clan_id:    int
    hero_slots: Optional[int] = None


class CoalitionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id:             int
    spawn_id:       int
    leader_clan_id: int
    name:           Optional[str]
    status:         str
    loot_rule:      str


class AccessRankingOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    clan_id:    int
    points:     int
    qualified:  bool
    cycle_key:  str


# ═══════════════════════════════════════════════════════════════════════════════
# Boss & Spawn endpoints
# ═══════════════════════════════════════════════════════════════════════════════

@router.get("/", response_model=List[SpawnOut])
async def list_active_spawns(
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    """List all currently open raid boss spawns."""
    svc = SpawnService(db)
    await svc.tick()
    return await svc.list_active_spawns()


@router.get("/calendar", response_model=List[Dict])
async def get_calendar(
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    """Return upcoming spawns grouped by category for the calendar UI."""
    result = await db.execute(select(RaidBossTemplate))
    templates = list(result.scalars().all())

    calendar = []
    for t in templates:
        cfg = t.spawn_config
        calendar.append({
            "template_id":   t.id,
            "code":          t.code,
            "name":          t.name,
            "category":      t.category.value,
            "interval_hours": cfg.get("interval_hours"),
            "window_minutes": cfg.get("window_minutes"),
            "requires_qualification": t.requires_qualification,
            "min_access_points":      t.min_access_points,
            "max_clans":  t.max_clans,
            "max_heroes": t.max_heroes,
        })
    return calendar


@router.get("/{template_id}", response_model=Dict)
async def get_boss_detail(
    template_id: int,
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    """Full boss detail — template + progress + active mutations + phases."""
    template = await db.get(RaidBossTemplate, template_id)
    if not template:
        raise HTTPException(404, "Boss template not found")

    result = await db.execute(
        select(RaidBossProgress).where(
            RaidBossProgress.template_id == template_id
        )
    )
    progress = result.scalar_one_or_none()

    result_m = await db.execute(
        select(RaidBossMutation).where(
            RaidBossMutation.progress_id == (progress.id if progress else -1),
            RaidBossMutation.is_active == True,
        )
    )
    mutations = list(result_m.scalars().all())

    result_ph = await db.execute(
        select(RaidBossPhase)
        .where(RaidBossPhase.template_id == template_id)
        .order_by(RaidBossPhase.phase_number)
    )
    phases = list(result_ph.scalars().all())

    return {
        "template": BossDetailOut.model_validate(template).model_dump(),
        "progress": ProgressOut.model_validate(progress).model_dump() if progress else None,
        "mutations": [MutationOut.model_validate(m).model_dump() for m in mutations],
        "phases":    [PhaseOut.model_validate(p).model_dump() for p in phases],
    }


@router.get("/{template_id}/loot", response_model=List[LootEntryOut])
async def get_loot_table(
    template_id: int,
    boss_level:  int = Query(1, ge=1),
    no_deaths:   bool = Query(False),
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    """Full loot table with adjusted chances. Shown in raid room before fight."""
    svc = RaidRewardService(db)
    entries = await svc.get_loot_preview(template_id, boss_level, no_deaths)
    return entries


@router.get("/{template_id}/history", response_model=List[HistoryOut])
async def get_boss_history(
    template_id: int,
    limit:       int = Query(10, le=50),
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    result = await db.execute(
        select(RaidBossHistory)
        .where(RaidBossHistory.template_id == template_id)
        .order_by(RaidBossHistory.occurred_at.desc())
        .limit(limit)
    )
    return list(result.scalars().all())


@router.post("/seed")
async def seed_bosses(
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    """Seed all 9 boss templates. Safe to call multiple times (idempotent)."""
    svc = SpawnService(db)
    templates = await svc.ensure_templates_exist()
    return {"seeded": len(templates), "codes": [t.code for t in templates]}


@router.post("/spawn/{template_id}")
async def manual_spawn(
    template_id: int,
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    """Manually create a spawn for a template (admin/testing)."""
    template = await db.get(RaidBossTemplate, template_id)
    if not template:
        raise HTTPException(404, "Template not found")
    svc   = SpawnService(db)
    spawn = await svc.schedule_next_spawn(template)
    # Immediately open it
    spawn.status = SpawnStatus.open
    await db.commit()
    return SpawnOut.model_validate(spawn).model_dump()


# ═══════════════════════════════════════════════════════════════════════════════
# Raid Room endpoints
# ═══════════════════════════════════════════════════════════════════════════════

@rooms_router.post("/create", response_model=RoomOut)
async def create_room(
    payload: CreateRoomIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    svc = RoomService(db)
    room = await svc.create_room(
        spawn_id        = payload.spawn_id,
        creator_user_id = user["user_id"],
        creator_clan_id = payload.clan_id,
        loot_rule       = payload.loot_rule,
    )
    return room


@rooms_router.get("/{room_id}", response_model=Dict)
async def get_room(
    room_id: int,
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    svc = RoomService(db)
    room = await svc.get_room(room_id)
    if not room:
        raise HTTPException(404, "Room not found")
    participants = await svc.get_participants(room_id)
    return {
        "room":         RoomOut.model_validate(room).model_dump(),
        "participants": [ParticipantOut.model_validate(p).model_dump()
                         for p in participants],
        "hero_count":   len(participants),
    }


@rooms_router.post("/{room_id}/join", response_model=ParticipantOut)
async def join_room(
    room_id: int,
    payload: JoinRoomIn,
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    svc = RoomService(db)
    try:
        p = await svc.join_room(room_id, payload.user_id,
                                payload.hero_id, payload.clan_id)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return p


@rooms_router.post("/{room_id}/ready")
async def set_ready(
    room_id: int,
    hero_id: int = Query(...),
    ready:   bool = Query(True),
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    svc = RoomService(db)
    await svc.set_ready(room_id, hero_id, ready)
    return {"ok": True}


@rooms_router.post("/{room_id}/lock", response_model=RoomOut)
async def lock_roster(
    room_id: int,
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    svc = RoomService(db)
    try:
        room = await svc.lock_roster(room_id)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return room


@rooms_router.post("/{room_id}/start", response_model=BattleResultOut)
async def start_raid(
    room_id: int,
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    """Lock and immediately run the raid simulation."""
    svc = RoomService(db)
    room = await svc.get_room(room_id)
    if not room:
        raise HTTPException(404, "Room not found")
    from app.database.models.raid_v2 import RoomStatus
    if room.status == RoomStatus.preparing:
        await svc.lock_roster(room_id)

    battle_svc = RaidBattleService(db)
    try:
        result = await battle_svc.run_battle(room_id)
    except Exception as e:
        raise HTTPException(400, str(e))

    # If victory → distribute rewards
    if result.outcome == "victory":
        log_result = await db.execute(
            select(RaidBattleLog).where(RaidBattleLog.room_id == room_id)
        )
        log = log_result.scalar_one_or_none()
        if log:
            reward_svc = RaidRewardService(db)
            spawn = await db.get(RaidBossSpawn, log.spawn_id)
            template = await db.get(RaidBossTemplate, spawn.template_id)
            progress_result = await db.execute(
                select(RaidBossProgress).where(
                    RaidBossProgress.template_id == template.id
                )
            )
            progress = progress_result.scalar_one_or_none()
            ctx = {
                "boss_level": progress.current_level if progress else 1,
                "no_deaths":  all(c["score"] > 0 for c in result.contributions),
            }
            await reward_svc.distribute(room_id, log, result.contributions, ctx)

    return BattleResultOut(
        outcome               = result.outcome,
        total_ticks           = result.total_ticks,
        phases_broken         = result.phases_broken,
        boss_hp_remaining_pct = result.boss_hp_remaining_pct,
        boss_xp_gained        = result.boss_xp_gained,
        level_before          = result.level_before,
        level_after           = result.level_after,
        mutation_gained       = result.mutation_gained,
        summary               = result.summary,
        contributions         = result.contributions,
    )


@rooms_router.get("/{room_id}/result", response_model=Dict)
async def get_raid_result(
    room_id: int,
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    log_result = await db.execute(
        select(RaidBattleLog).where(RaidBattleLog.room_id == room_id)
    )
    log = log_result.scalar_one_or_none()
    if not log:
        raise HTTPException(404, "No result yet for this room")

    contribs_result = await db.execute(
        select(RaidContribution).where(RaidContribution.room_id == room_id)
    )
    contribs = list(contribs_result.scalars().all())

    rolls_result = await db.execute(
        select(RaidRewardRoll).where(RaidRewardRoll.battle_log_id == log.id)
    )
    rolls = list(rolls_result.scalars().all())

    return {
        "outcome":      log.outcome,
        "total_ticks":  log.total_ticks,
        "phases_broken": log.phases_broken,
        "boss_hp_remaining_pct": log.boss_hp_remaining_pct,
        "summary":      log.summary,
        "contributions": [
            {
                "user_id":            c.user_id,
                "hero_id":            c.hero_id,
                "damage_dealt":       c.damage_dealt,
                "damage_taken":       c.damage_taken,
                "healing_done":       c.healing_done,
                "kills":              c.kills,
                "survival_ticks":     c.survival_ticks,
                "contribution_score": c.contribution_score,
                "contribution_pct":   round(c.contribution_pct * 100, 1),
                "is_mvp":             c.is_mvp,
            }
            for c in contribs
        ],
        "rewards": [
            {
                "user_id":      r.user_id,
                "clan_id":      r.clan_id,
                "display_name": r.display_name,
                "rarity":       r.rarity.value,
                "quantity":     r.quantity,
                "is_ultra_rare": r.is_ultra_rare,
                "ownership":    r.ownership.value,
            }
            for r in rolls
        ],
    }


# ═══════════════════════════════════════════════════════════════════════════════
# Coalition endpoints
# ═══════════════════════════════════════════════════════════════════════════════

@coalition_router.post("/create", response_model=CoalitionOut)
async def create_coalition(
    payload: CreateCoalitionIn,
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    svc = RoomService(db)
    try:
        coalition = await svc.create_coalition(
            spawn_id       = payload.spawn_id,
            leader_clan_id = payload.leader_clan_id,
            loot_rule      = payload.loot_rule,
            name           = payload.name,
        )
    except ValueError as e:
        raise HTTPException(400, str(e))
    return coalition


@coalition_router.post("/{coalition_id}/invite")
async def invite_clan(
    coalition_id: int,
    payload: InviteClanIn,
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    svc = RoomService(db)
    try:
        invite = await svc.invite_clan(coalition_id, payload.clan_id, payload.hero_slots)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return {"coalition_id": coalition_id, "clan_id": payload.clan_id, "invited": True}


@coalition_router.post("/{coalition_id}/accept")
async def accept_invite(
    coalition_id: int,
    clan_id: int = Query(...),
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    svc = RoomService(db)
    try:
        invite = await svc.accept_invite(coalition_id, clan_id)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return {"accepted": True, "hero_slots": invite.hero_slots}


@coalition_router.get("/{coalition_id}", response_model=Dict)
async def get_coalition(
    coalition_id: int,
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    coalition = await db.get(RaidCoalition, coalition_id)
    if not coalition:
        raise HTTPException(404, "Coalition not found")
    result = await db.execute(
        select(RaidCoalitionClan).where(
            RaidCoalitionClan.coalition_id == coalition_id
        )
    )
    clans = list(result.scalars().all())
    return {
        "coalition": CoalitionOut.model_validate(coalition).model_dump(),
        "clans": [
            {"clan_id": c.clan_id, "hero_slots": c.hero_slots, "accepted": c.accepted}
            for c in clans
        ],
    }


# ═══════════════════════════════════════════════════════════════════════════════
# Access Score endpoints
# ═══════════════════════════════════════════════════════════════════════════════

@access_router.get("/ranking", response_model=List[AccessRankingOut])
async def get_access_ranking(
    cycle:  str = Query("weekly", regex="^(weekly|monthly)$"),
    limit:  int = Query(20, le=50),
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    svc = AccessService(db)
    return await svc.get_ranking(cycle, limit)


@access_router.get("/my-score", response_model=Optional[AccessRankingOut])
async def get_my_score(
    cycle:   str = Query("weekly", regex="^(weekly|monthly)$"),
    clan_id: int = Query(...),
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    svc = AccessService(db)
    return await svc.get_clan_score(clan_id, cycle)


@access_router.post("/add")
async def add_access_points(
    clan_id: int,
    points:  int,
    cycle:   str = Query("weekly", regex="^(weekly|monthly)$"),
    db: AsyncSession = Depends(get_session),
    _user=Depends(get_current_user_info),
):
    svc = AccessService(db)
    row = await svc.add_points(clan_id, points, cycle)
    return {"clan_id": clan_id, "points": row.points, "cycle_key": row.cycle_key}
