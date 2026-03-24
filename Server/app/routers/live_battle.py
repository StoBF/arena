"""
live_battle.py — REST + WebSocket API for real-time 5v5 battles.

Endpoints
---------
POST  /live-battles/create       Create battle from two hero lists
POST  /live-battles/{id}/start   Start the simulation
GET   /live-battles/{id}         Status / info
POST  /live-battles/{id}/stop    Force-stop
GET   /live-battles/             List active battles

WS    /ws/live-battles/{id}      Subscribe to snapshots + events
"""
from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List

from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.session import get_db
from app.database.models.live_battle import (
    BattleOutcome, LiveBattleEventLog, LiveBattleHeroResult, LiveBattleSession,
)
from app.services.live_battle import LiveBattleSimulator, battle_registry
from app.services.live_battle.runtime import BattleStatus
from app.services.reward_distributor import RewardDistributor

log = logging.getLogger(__name__)
router = APIRouter(prefix="/live-battles", tags=["live-battles"])

# ── Pydantic schemas ──────────────────────────────────────────────────────────

class HeroEntrySchema(BaseModel):
    id:           int
    user_id:      int
    name:         str = ""
    primary_role: str = "VANGUARD"
    secondary_role: str | None = None
    stats: Dict[str, Any] = {}
    skills: List[Dict[str, Any]] = []

class CreateBattleRequest(BaseModel):
    heroes_a: List[HeroEntrySchema]
    heroes_b: List[HeroEntrySchema]
    map_id:   str = "arena_skirmish"

# ── REST endpoints ────────────────────────────────────────────────────────────

@router.post("/create")
async def create_battle(req: CreateBattleRequest, db: AsyncSession = Depends(get_db)):
    """Create a new battle instance and return its battle_id."""
    if len(req.heroes_a) < 1 or len(req.heroes_b) < 1:
        raise HTTPException(400, "Need at least 1 hero per team")

    sim = LiveBattleSimulator.create(
        heroes_a = [h.model_dump() for h in req.heroes_a],
        heroes_b = [h.model_dump() for h in req.heroes_b],
        map_id   = req.map_id,
    )
    b = sim.battle

    # Persist session record
    session_row = LiveBattleSession(
        battle_uuid     = b.battle_id,
        map_id          = b.map_id,
        mode            = b.mode,
        status          = "pending",
        team_a_user_ids = b.team_a.user_ids if b.team_a else [],
        team_b_user_ids = b.team_b.user_ids if b.team_b else [],
    )
    db.add(session_row)
    await db.commit()

    # Store simulator in registry (already done in create())
    # Store the sim object keyed by battle_id
    _sim_registry[b.battle_id] = sim

    return {"battle_id": b.battle_id, "status": b.status.value}


@router.post("/{battle_id}/start")
async def start_battle(battle_id: str, db: AsyncSession = Depends(get_db)):
    sim = _sim_registry.get(battle_id)
    if sim is None:
        raise HTTPException(404, "Battle not found")
    if sim.battle.status != BattleStatus.PENDING:
        raise HTTPException(400, f"Battle is {sim.battle.status.value}")

    sim.battle.started_at = datetime.now(timezone.utc)
    sim.start()

    # Update DB
    from sqlalchemy import update
    from app.database.models.live_battle import LiveBattleSession as LBS
    await db.execute(
        update(LBS)
        .where(LBS.battle_uuid == battle_id)
        .values(status="running", started_at=sim.battle.started_at)
    )
    await db.commit()
    return {"battle_id": battle_id, "status": "running"}


@router.get("/{battle_id}")
async def get_battle(battle_id: str):
    b = battle_registry.get(battle_id)
    if b is None:
        raise HTTPException(404, "Battle not found")
    return {
        "battle_id":    b.battle_id,
        "status":       b.status.value,
        "tick":         b.current_tick,
        "elapsed":      round(b.elapsed_time, 2),
        "winner":       b.winner_team,
        "team_a_alive": sum(1 for h in b.heroes.values() if h.team_id == "A" and not h.dead),
        "team_b_alive": sum(1 for h in b.heroes.values() if h.team_id == "B" and not h.dead),
        "heroes": [
            {
                "hero_id":  h.hero_id,
                "name":     h.name,
                "team_id":  h.team_id,
                "role":     h.primary_role,
                "hp_pct":   round(h.hp_pct, 2),
                "alive":    h.alive,
                "kills":    h.kills,
            }
            for h in b.heroes.values()
        ],
    }


@router.post("/{battle_id}/stop")
async def stop_battle(battle_id: str, db: AsyncSession = Depends(get_db)):
    sim = _sim_registry.get(battle_id)
    if sim is None:
        raise HTTPException(404, "Battle not found")
    sim.stop()
    await _persist_result(sim.battle, db)
    return {"ok": True, "battle_id": battle_id}


@router.get("/")
async def list_battles(
    status: str | None = Query(None, description="Filter by status")
):
    battles = list(battle_registry.values())
    if status:
        battles = [b for b in battles if b.status.value == status]
    return [
        {"battle_id": b.battle_id, "status": b.status.value,
         "tick": b.current_tick, "winner": b.winner_team}
        for b in battles
    ]

# ── WebSocket subscription ────────────────────────────────────────────────────

@router.websocket("/ws/{battle_id}")
async def ws_subscribe(ws: WebSocket, battle_id: str):
    """
    WebSocket: subscribe to real-time snapshots for a battle.
    The server pushes a JSON frame every tick (100 ms).
    """
    b = battle_registry.get(battle_id)
    if b is None:
        await ws.close(code=4404)
        return

    await ws.accept()

    async def send_fn(data: str):
        await ws.send_text(data)

    b.subscribers.append(send_fn)
    log.info("WS client joined battle %s (subscribers: %d)", battle_id, len(b.subscribers))

    # Send initial state
    await ws.send_text(json.dumps({
        "type":      "hello",
        "battle_id": battle_id,
        "status":    b.status.value,
        "tick_rate": b.tick_rate,
        "heroes": [
            {"hero_id": h.hero_id, "name": h.name, "team_id": h.team_id,
             "role": h.primary_role, "pos": h.position.to_dict()}
            for h in b.heroes.values()
        ],
    }))

    try:
        while True:
            # Keep connection alive; incoming messages are ignored (spectator only)
            msg = await ws.receive_text()
            # Could handle client commands here in the future
    except WebSocketDisconnect:
        pass
    finally:
        if send_fn in b.subscribers:
            b.subscribers.remove(send_fn)
        log.info("WS client left battle %s", battle_id)


# ── Persistence helpers ───────────────────────────────────────────────────────

# Local sim registry (simulator objects, keyed by battle_id)
_sim_registry: Dict[str, LiveBattleSimulator] = {}


async def _persist_result(battle, db: AsyncSession) -> None:
    """Write final battle stats to DB."""
    from sqlalchemy import update, select
    from app.database.models.live_battle import LiveBattleSession as LBS

    result = await db.execute(
        select(LBS).where(LBS.battle_uuid == battle.battle_id)
    )
    row = result.scalar_one_or_none()
    if row is None:
        return

    winner = battle.winner_team or "draw"
    outcome_map = {"A": BattleOutcome.TEAM_A_WIN, "B": BattleOutcome.TEAM_B_WIN,
                   "draw": BattleOutcome.DRAW}

    row.status          = battle.status.value
    row.outcome         = outcome_map.get(winner, BattleOutcome.CANCELLED)
    row.winner_team     = winner
    row.total_ticks     = battle.current_tick
    row.elapsed_seconds = battle.elapsed_time
    row.finished_at     = datetime.now(timezone.utc)

    # Hero results
    for h in battle.heroes.values():
        db.add(LiveBattleHeroResult(
            session_id      = row.id,
            hero_id         = h.hero_id,
            user_id         = h.user_id,
            team_id         = h.team_id,
            primary_role    = h.primary_role,
            damage_dealt    = h.damage_dealt,
            damage_taken    = h.damage_taken,
            kills           = h.kills,
            control_seconds = h.control_seconds,
            survived        = h.alive,
            final_hp_pct    = h.hp_pct,
            final_stamina_pct = h.stamina_pct,
        ))

    # Key events (limit to important ones for storage efficiency)
    important_types = {
        "hero_dead", "hero_unconscious", "kill_trigger", "absorb_trigger",
        "cast_interrupted", "cast_redirected", "battle_finished",
    }
    for ev in battle.event_log:
        if ev.event_type.value in important_types:
            db.add(LiveBattleEventLog(
                session_id     = row.id,
                tick           = ev.tick,
                event_type     = ev.event_type.value,
                source_hero_id = ev.source_id,
                target_hero_id = ev.target_id,
                position_x     = ev.position.x if ev.position else None,
                position_z     = ev.position.z if ev.position else None,
                payload        = ev.payload,
            ))

    await db.commit()

    # ── Reward distribution ───────────────────────────────────────────────────
    # Build hero_results dict keyed by user_id for contribution scaling
    hero_results: dict = {}
    for h in battle.heroes.values():
        hero_results[h.user_id] = {
            "damage_dealt":    h.damage_dealt,
            "kills":           h.kills,
            "control_seconds": h.control_seconds,
            "survived":        h.alive,
        }

    team_a_users = battle.team_a.user_ids if battle.team_a else []
    team_b_users = battle.team_b.user_ids if battle.team_b else []
    winner = battle.winner_team or "draw"

    try:
        dist = RewardDistributor(db)
        await dist.distribute_live_battle(
            winner_team      = winner,
            team_a_user_ids  = team_a_users,
            team_b_user_ids  = team_b_users,
            hero_results     = hero_results,
        )
    except Exception as exc:
        log.warning("Live battle reward distribution failed for %s: %s", battle.battle_id, exc)
