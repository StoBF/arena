"""
Battle Room router — tactical pre-battle planning + simulation.

Endpoints:
  POST /battle/room/create          Create room, become team A
  POST /battle/room/{id}/join       Join room as team B
  POST /battle/room/{id}/order      Submit / update hero order
  POST /battle/room/{id}/directive  Set team directive (captain)
  POST /battle/room/{id}/ready      Mark self as ready; triggers sim when all ready
  GET  /battle/room/{id}            Fetch room state
  GET  /battle/room/{id}/result     Fetch battle result + rewards
  POST /battle/room/{id}/cancel     Cancel room

WebSocket:
  WS /ws/battle/{room_id}          Real-time order sync within the room
"""
from __future__ import annotations

import json
import asyncio
from datetime import datetime
from typing import Any, Dict, List, Optional

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.auth import get_current_user_info
from app.database.session import get_session
from app.database.models.battle_room import (
    BattleRoom, BattleResult, BattleRoomStatus, HeroOrder, HeroStance,
    PlayerResourceInventory,
)
from app.database.models.hero import Hero, HeroStats
from app.services.battle_sim import BattleSimulator, CombatHero
from app.services.reward_distributor import RewardDistributor

router = APIRouter(prefix="/battle/room", tags=["Battle Room"])

# ── Simple in-memory WS manager for battle rooms ─────────────────────────────
_room_connections: Dict[int, List[WebSocket]] = {}


async def _broadcast(room_id: int, msg: dict):
    conns = _room_connections.get(room_id, [])
    dead = []
    for ws in conns:
        try:
            await ws.send_text(json.dumps(msg))
        except Exception:
            dead.append(ws)
    for d in dead:
        conns.remove(d)


# ── Schemas ───────────────────────────────────────────────────────────────────

class CreateRoomIn(BaseModel):
    hero_ids: List[int]


class JoinRoomIn(BaseModel):
    hero_ids: List[int]


class HeroOrderIn(BaseModel):
    hero_id:          int
    stance:           HeroStance = HeroStance.attack
    primary_action:   str = "basic_attack"
    primary_target:   Optional[str] = None
    fallback_rule:    Optional[str] = None
    reactive_trigger: Optional[str] = None


class DirectiveIn(BaseModel):
    opening_mode:    Optional[str] = None
    priority_target: Optional[str] = None
    protected_ally:  Optional[str] = None
    control_target:  Optional[str] = None
    phase_trigger:   Optional[str] = None


# ── Helpers ───────────────────────────────────────────────────────────────────

def _room_dict(room: BattleRoom) -> dict:
    return {
        "id":                room.id,
        "status":            room.status.value,
        "team_a_ids":        room.team_a_ids,
        "team_b_ids":        room.team_b_ids,
        "team_a_directives": room.team_a_directives,
        "team_b_directives": room.team_b_directives,
        "ready_a":           room.ready_a,
        "ready_b":           room.ready_b,
        "created_at":        room.created_at.isoformat(),
    }


async def _load_combat_hero(db: AsyncSession, hero: Hero,
                             order: Optional[HeroOrder], team: str) -> CombatHero:
    stats_row = await db.execute(
        select(HeroStats).where(HeroStats.hero_id == hero.id)
    )
    stats = stats_row.scalars().first()
    return CombatHero(
        hero_id=hero.id,
        user_id=hero.owner_id,
        team=team,
        name=hero.name,
        hp=hero.current_hp or 100,
        max_hp=hero.current_hp or 100,
        stamina=stats.stamina if stats else 100,
        willpower=stats.willpower if stats else 5,
        strength=stats.strength if stats else 10,
        agility=stats.agility if stats else 10,
        defense=stats.defense if stats else 5,
        stance=order.stance.value if order else "attack",
        primary_action=order.primary_action if order else "basic_attack",
        primary_target=order.primary_target if order else None,
        fallback_rule=order.fallback_rule if order else None,
        reactive_trigger=order.reactive_trigger if order else None,
    )


async def _simulate_and_persist(room_id: int, db: AsyncSession):
    """Run battle simulation and persist results."""
    room = await db.get(BattleRoom, room_id)
    if not room:
        return

    room.status = BattleRoomStatus.simulating
    room.started_at = datetime.utcnow()
    await db.commit()

    # Load heroes
    orders_res = await db.execute(
        select(HeroOrder).where(HeroOrder.room_id == room_id)
    )
    orders: Dict[int, HeroOrder] = {o.hero_id: o for o in orders_res.scalars().all()}

    async def load_team(ids: List[int], team: str) -> List[CombatHero]:
        heroes_res = await db.execute(select(Hero).where(Hero.id.in_(ids)))
        heroes = list(heroes_res.scalars().all())
        return [await _load_combat_hero(db, h, orders.get(h.id), team) for h in heroes]

    team_a = await load_team(room.team_a_ids, "a")
    team_b = await load_team(room.team_b_ids, "b")

    sim_result = BattleSimulator(team_a, team_b).run()
    winner = sim_result["winner_team"]

    # Distribute rewards
    dist = RewardDistributor(db)
    rewards = await dist.distribute_pvp(
        winner_team=winner,
        team_a_ids=room.team_a_ids,
        team_b_ids=room.team_b_ids,
    )

    # Persist result
    result = BattleResult(
        room_id=room_id,
        winner_team=winner,
        battle_log=sim_result["log"],
        rewards={str(k): v for k, v in rewards.items()},
    )
    db.add(result)
    room.status = BattleRoomStatus.completed
    room.finished_at = datetime.utcnow()
    await db.commit()

    await _broadcast(room_id, {
        "event": "battle_complete",
        "winner_team": winner,
        "rewards": {str(k): v for k, v in rewards.items()},
    })


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/create", summary="Create a battle room (team A)")
async def create_room(
    body: CreateRoomIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    user_id = user["user_id"]
    # Validate hero ownership
    res = await db.execute(
        select(Hero).where(Hero.id.in_(body.hero_ids), Hero.owner_id == user_id)
    )
    if len(list(res.scalars().all())) != len(body.hero_ids):
        raise HTTPException(400, "Invalid hero selection")

    room = BattleRoom(
        creator_id=user_id,
        team_a_ids=[user_id],
        team_b_ids=[],
        team_a_directives={},
        team_b_directives={},
        ready_a=[],
        ready_b=[],
    )
    db.add(room)
    await db.commit()
    await db.refresh(room)
    return _room_dict(room)


@router.post("/{room_id}/join", summary="Join a room as team B")
async def join_room(
    room_id: int,
    body: JoinRoomIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    user_id = user["user_id"]
    room = await db.get(BattleRoom, room_id)
    if not room or room.status != BattleRoomStatus.waiting:
        raise HTTPException(404, "Room not available")
    if user_id in room.team_a_ids:
        raise HTTPException(400, "Already in team A")

    res = await db.execute(
        select(Hero).where(Hero.id.in_(body.hero_ids), Hero.owner_id == user_id)
    )
    if len(list(res.scalars().all())) != len(body.hero_ids):
        raise HTTPException(400, "Invalid hero selection")

    room.team_b_ids = [user_id]
    room.status = BattleRoomStatus.planning
    await db.commit()
    await _broadcast(room_id, {"event": "player_joined", "user_id": user_id})
    return _room_dict(room)


@router.post("/{room_id}/order", summary="Submit or update a hero order")
async def submit_order(
    room_id: int,
    body: HeroOrderIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    user_id = user["user_id"]
    room = await db.get(BattleRoom, room_id)
    if not room or room.status != BattleRoomStatus.planning:
        raise HTTPException(400, "Room not in planning phase")
    if user_id not in room.team_a_ids + room.team_b_ids:
        raise HTTPException(403, "Not in this room")

    # Verify hero ownership
    hero = await db.get(Hero, body.hero_id)
    if not hero or hero.owner_id != user_id:
        raise HTTPException(403, "Hero not yours")

    # Upsert order
    res = await db.execute(
        select(HeroOrder).where(
            HeroOrder.room_id == room_id, HeroOrder.hero_id == body.hero_id
        )
    )
    order = res.scalars().first()
    if order is None:
        order = HeroOrder(room_id=room_id, user_id=user_id, hero_id=body.hero_id)
        db.add(order)

    order.stance           = body.stance
    order.primary_action   = body.primary_action
    order.primary_target   = body.primary_target
    order.fallback_rule    = body.fallback_rule
    order.reactive_trigger = body.reactive_trigger
    await db.commit()

    order_dict = {
        "hero_id": body.hero_id,
        "stance": body.stance.value,
        "primary_action": body.primary_action,
        "primary_target": body.primary_target,
        "fallback_rule": body.fallback_rule,
        "reactive_trigger": body.reactive_trigger,
    }
    await _broadcast(room_id, {"event": "order_updated", "order": order_dict})
    return order_dict


@router.post("/{room_id}/directive", summary="Set team directive (any team member)")
async def set_directive(
    room_id: int,
    body: DirectiveIn,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    user_id = user["user_id"]
    room = await db.get(BattleRoom, room_id)
    if not room or room.status != BattleRoomStatus.planning:
        raise HTTPException(400, "Room not in planning phase")

    directive = body.model_dump(exclude_none=True)
    if user_id in room.team_a_ids:
        room.team_a_directives = directive
    elif user_id in room.team_b_ids:
        room.team_b_directives = directive
    else:
        raise HTTPException(403, "Not in this room")

    await db.commit()
    await _broadcast(room_id, {"event": "directive_updated", "team": "a" if user_id in room.team_a_ids else "b", "directive": directive})
    return {"ok": True}


@router.post("/{room_id}/ready", summary="Mark yourself ready; triggers sim when all ready")
async def mark_ready(
    room_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    user_id = user["user_id"]
    room = await db.get(BattleRoom, room_id)
    if not room or room.status != BattleRoomStatus.planning:
        raise HTTPException(400, "Room not in planning phase")

    if user_id in room.team_a_ids and user_id not in room.ready_a:
        room.ready_a = room.ready_a + [user_id]
    elif user_id in room.team_b_ids and user_id not in room.ready_b:
        room.ready_b = room.ready_b + [user_id]
    else:
        raise HTTPException(403, "Not in this room or already ready")

    await db.commit()
    await _broadcast(room_id, {"event": "player_ready", "user_id": user_id})

    # Auto-simulate when all members of both teams are ready
    all_a_ready = set(room.ready_a) >= set(room.team_a_ids)
    all_b_ready = set(room.ready_b) >= set(room.team_b_ids)
    if all_a_ready and all_b_ready and room.team_b_ids:
        asyncio.create_task(_simulate_and_persist(room_id, db))

    return {"ok": True, "ready_a": room.ready_a, "ready_b": room.ready_b}


@router.get("/{room_id}", summary="Get room state")
async def get_room(
    room_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    room = await db.get(BattleRoom, room_id)
    if not room:
        raise HTTPException(404, "Room not found")
    return _room_dict(room)


@router.get("/{room_id}/result", summary="Get battle result + per-player rewards")
async def get_result(
    room_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    res = await db.execute(
        select(BattleResult).where(BattleResult.room_id == room_id)
    )
    result = res.scalars().first()
    if not result:
        raise HTTPException(404, "Battle result not ready yet")
    return {
        "room_id":     room_id,
        "winner_team": result.winner_team,
        "battle_log":  result.battle_log,
        "rewards":     result.rewards,
        "finished_at": result.created_at.isoformat(),
    }


@router.post("/{room_id}/cancel", summary="Cancel a battle room")
async def cancel_room(
    room_id: int,
    db: AsyncSession = Depends(get_session),
    user=Depends(get_current_user_info),
):
    room = await db.get(BattleRoom, room_id)
    if not room:
        raise HTTPException(404, "Room not found")
    if room.status in (BattleRoomStatus.completed, BattleRoomStatus.simulating):
        raise HTTPException(400, "Cannot cancel a completed/simulating room")
    room.status = BattleRoomStatus.cancelled
    await db.commit()
    await _broadcast(room_id, {"event": "room_cancelled"})
    return {"ok": True}


# ── WebSocket ─────────────────────────────────────────────────────────────────

@router.websocket("/ws/{room_id}")
async def battle_room_ws(room_id: int, websocket: WebSocket):
    await websocket.accept()
    _room_connections.setdefault(room_id, []).append(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            # Broadcast any client message to everyone else in the room
            await _broadcast(room_id, msg)
    except WebSocketDisconnect:
        conns = _room_connections.get(room_id, [])
        if websocket in conns:
            conns.remove(websocket)
