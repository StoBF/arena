"""
simulator.py — LiveBattleSimulator

Orchestrates the full 9-phase tick pipeline at 10 ticks/second.
All state is in-memory; persistence happens on battle end.

Public API
----------
  LiveBattleSimulator.create(params) -> BattleInstance
  LiveBattleSimulator.start(battle_id)
  LiveBattleSimulator.stop(battle_id)
  battle_registry: dict[str, BattleInstance]   ← global registry
"""
from __future__ import annotations

import asyncio
import json
import logging
import time
from typing import Any, Dict, List, Optional

from .arena import (
    ROLE_PREFERRED_RANGE, ROLE_SPEED_MOD,
    facing_angle, navigate, spawn_positions_team_a, spawn_positions_team_b,
)
from .hero_ai import decide, pick_assist_target
from .runtime import (
    BattleInstance, BattleSnapshot, BattleStatus, BattleTeamRuntime,
    EventType, BattleEvent, HeroRuntimeState, HeroSnapshot, HeroState, Vec2,
)
from .skill_resolver import resolve_basic_attack, resolve_cast, tick_effects

log = logging.getLogger(__name__)

# Global registry: battle_id → BattleInstance
battle_registry: Dict[str, BattleInstance] = {}

SIM_TICK_RATE = 10   # ticks per second
TICK_INTERVAL = 1.0 / SIM_TICK_RATE


# ── Main simulator class ──────────────────────────────────────────────────────

class LiveBattleSimulator:
    """One instance per active battle, runs as an asyncio task."""

    def __init__(self, battle: BattleInstance):
        self.battle = battle
        self._task: Optional[asyncio.Task] = None

    # ── Factory ────────────────────────────────────────────────────────────────

    @classmethod
    def create(
        cls,
        heroes_a: List[Dict[str, Any]],
        heroes_b: List[Dict[str, Any]],
        map_id:   str = "arena_skirmish",
    ) -> "LiveBattleSimulator":
        """
        Build a BattleInstance from two lists of hero dicts (loaded from DB).
        Each hero dict must have: id, user_id, name, primary_role,
        secondary_role?, stats{hp,stamina,defense,vision,speed,agility,luck,
        willpower,attack_power}, skills[{id,name,family,cast_time,cooldown,
        power,range,stamina_cost,interruptible,redirectable,...}]
        """
        battle = BattleInstance(map_id=map_id, tick_rate=SIM_TICK_RATE)
        battle_registry[battle.battle_id] = battle

        pos_a = spawn_positions_team_a(len(heroes_a))
        pos_b = spawn_positions_team_b(len(heroes_b))

        for i, hd in enumerate(heroes_a):
            h = _build_hero(hd, "A", pos_a[i])
            battle.heroes[h.hero_id] = h

        for i, hd in enumerate(heroes_b):
            h = _build_hero(hd, "B", pos_b[i])
            battle.heroes[h.hero_id] = h

        battle.team_a = BattleTeamRuntime(
            team_id  = "A",
            user_ids = [hd["user_id"] for hd in heroes_a],
            hero_ids = [hd["id"] for hd in heroes_a],
        )
        battle.team_b = BattleTeamRuntime(
            team_id  = "B",
            user_ids = [hd["user_id"] for hd in heroes_b],
            hero_ids = [hd["id"] for hd in heroes_b],
        )
        return cls(battle)

    # ── Lifecycle ──────────────────────────────────────────────────────────────

    def start(self) -> asyncio.Task:
        self.battle.status = BattleStatus.RUNNING
        self._task = asyncio.create_task(self._run_loop())
        return self._task

    def stop(self) -> None:
        if self._task and not self._task.done():
            self._task.cancel()
        self.battle.status = BattleStatus.CANCELLED

    # ── Main tick loop ─────────────────────────────────────────────────────────

    async def _run_loop(self) -> None:
        battle = self.battle
        log.info("Battle %s started", battle.battle_id)
        try:
            while battle.status == BattleStatus.RUNNING:
                tick_start = time.monotonic()
                await self._tick()
                elapsed = time.monotonic() - tick_start
                sleep_for = max(0.0, TICK_INTERVAL - elapsed)
                await asyncio.sleep(sleep_for)
        except asyncio.CancelledError:
            pass
        except Exception:
            log.exception("Battle %s crashed", battle.battle_id)
        finally:
            await self._finalize()

    async def _tick(self) -> None:
        b = self.battle
        dt = b.dt
        b.current_tick  += 1
        b.elapsed_time  += dt
        tick_events: List[BattleEvent] = []

        # 1. Pre-Tick Maintenance
        for h in b.heroes.values():
            if h.dead:
                continue
            _tick_cooldowns(h, dt)
            _tick_stamina(h, dt)
            tick_effects(h, dt, b)
            h.willpower_pressure = max(0.0, h.willpower_pressure - 0.5 * dt)

        # 2. Cast progress
        for h in b.heroes.values():
            if h.dead or h.current_cast is None:
                continue
            h.current_cast.elapsed += dt
            if not h.current_cast.committed and h.current_cast.elapsed >= h.current_cast.windup * 0.5:
                h.current_cast.committed = True
            if h.current_cast.done:
                resolve_cast(h, h.current_cast, b)
                h.current_cast = None
                h.state = HeroState.IDLE

        # 3. Status / control state (handled in tick_effects above)

        # 4+5. Decision + Movement Phase
        moves: Dict[int, Vec2] = {}
        for h in b.heroes.values():
            if h.dead or h.unconscious:
                continue
            dest = decide(h, b)
            if dest is not None and h.can_move:
                moves[h.hero_id] = dest

        # 5. Apply movement
        for hero_id, dest in moves.items():
            h = b.heroes[hero_id]
            step = h.speed * dt
            h.position = navigate(h.position, dest, step)
            if h.position.distance_to(dest) > 0.05:
                h.rotation = facing_angle(h.position, dest)

        # 6. Basic attack resolution
        for h in b.heroes.values():
            if not h.actionable or h.current_cast is not None:
                continue
            if h.target_id is None:
                continue
            target = b.hero(h.target_id)
            if target is None or target.dead:
                h.target_id = None
                continue
            dist = h.position.distance_to(target.position)
            if dist <= h.preferred_range + 0.8:
                h.last_attack_elapsed += dt
                if h.last_attack_elapsed >= h.attack_interval:
                    h.last_attack_elapsed = 0.0
                    resolve_basic_attack(h, target, b)

        # 7. Post-resolution: update team damage totals
        for side, team in (("A", b.team_a), ("B", b.team_b)):
            if team:
                team.total_damage = sum(
                    h.damage_dealt for h in b.heroes.values() if h.team_id == side
                )

        # 8. Win condition check
        a_alive = sum(1 for h in b.heroes.values() if h.team_id == "A" and not h.dead)
        b_alive = sum(1 for h in b.heroes.values() if h.team_id == "B" and not h.dead)

        finished = False
        if a_alive == 0 and b_alive == 0:
            b.winner_team = "draw"
            finished = True
        elif a_alive == 0:
            b.winner_team = "B"
            finished = True
        elif b_alive == 0:
            b.winner_team = "A"
            finished = True
        elif b.elapsed_time >= b.time_limit:
            b.winner_team = "A" if a_alive > b_alive else (
                "B" if b_alive > a_alive else "draw"
            )
            finished = True

        if finished:
            b.status = BattleStatus.FINISHED
            b.event_log.append(BattleEvent(
                tick       = b.current_tick,
                event_type = EventType.BATTLE_FINISHED,
                source_id  = None,
                target_id  = None,
                position   = None,
                payload    = {"winner": b.winner_team},
            ))

        # 9. Snapshot + broadcast
        snapshot = self._build_snapshot(a_alive, b_alive)
        await self._broadcast(snapshot)

        # Collect tick events into master log (done inline above via battle.event_log)

    def _build_snapshot(self, a_alive: int, b_alive: int) -> BattleSnapshot:
        b = self.battle
        hero_snaps = []
        for h in b.heroes.values():
            cast_name = h.current_cast.skill_name if h.current_cast else None
            ch_name   = cast_name if (h.current_cast and not h.current_cast.done and
                                      h.current_cast.action_type.value == "channel") else None
            hero_snaps.append(HeroSnapshot(
                hero_id       = h.hero_id,
                team_id       = h.team_id,
                position      = Vec2(h.position.x, h.position.z),
                rotation      = h.rotation,
                state         = h.state.value,
                target_id     = h.target_id,
                hp            = h.current_hp,
                stamina       = h.current_stamina,
                hp_pct        = h.hp_pct,
                stamina_pct   = h.stamina_pct,
                active_cast   = cast_name,
                active_channel = ch_name,
                control       = h.control_state.value if h.control_state else None,
                unconscious   = h.unconscious,
                dead          = h.dead,
                effects       = [e.sub_type for e in h.active_effects],
            ))
        # Only tick events (slice from last tick)
        tick_events = [e for e in b.event_log if e.tick == b.current_tick]
        return BattleSnapshot(
            tick         = b.current_tick,
            elapsed_time = b.elapsed_time,
            heroes       = hero_snaps,
            events       = tick_events,
            team_a_alive = a_alive,
            team_b_alive = b_alive,
        )

    async def _broadcast(self, snapshot: BattleSnapshot) -> None:
        if not self.battle.subscribers:
            return
        data = json.dumps({"type": "snapshot", **snapshot.to_dict()})
        dead = []
        for send_fn in self.battle.subscribers:
            try:
                await send_fn(data)
            except Exception:
                dead.append(send_fn)
        for fn in dead:
            self.battle.subscribers.remove(fn)

    async def _finalize(self) -> None:
        b = self.battle
        log.info("Battle %s finished — winner: %s (tick %d, %.1fs)",
                 b.battle_id, b.winner_team, b.current_tick, b.elapsed_time)
        # Notify subscribers of battle end
        data = json.dumps({
            "type":    "battle_finished",
            "winner":  b.winner_team,
            "tick":    b.current_tick,
            "elapsed": round(b.elapsed_time, 2),
        })
        for send_fn in b.subscribers:
            try:
                await send_fn(data)
            except Exception:
                pass
        b.subscribers.clear()
        # Remove from global registry to prevent memory leak
        try:
            if b.battle_id in battle_registry:
                del battle_registry[b.battle_id]
                log.info("Battle %s removed from registry", b.battle_id)
        except Exception:
            log.exception("Failed to remove battle %s from registry", b.battle_id)
        # DB persistence happens in the router after this completes


# ── Hero construction ─────────────────────────────────────────────────────────

def _build_hero(hd: Dict[str, Any], team_id: str, spawn: Vec2) -> HeroRuntimeState:
    stats    = hd.get("stats", {})
    role     = hd.get("primary_role", "VANGUARD").upper()
    sp_mod   = ROLE_SPEED_MOD.get(role, 1.0)
    pref_range = ROLE_PREFERRED_RANGE.get(role, 2.0)
    base_speed = float(stats.get("speed", 10))

    h = HeroRuntimeState(
        hero_id       = hd["id"],
        user_id       = hd["user_id"],
        name          = hd.get("name", f"Hero#{hd['id']}"),
        team_id       = team_id,
        primary_role  = role,
        secondary_role = hd.get("secondary_role"),
        position      = Vec2(spawn.x, spawn.z),
        desired_pos   = Vec2(spawn.x, spawn.z),
        max_hp        = float(stats.get("hp", 100)),
        current_hp    = float(stats.get("hp", 100)),
        max_stamina   = float(stats.get("stamina", 100)),
        current_stamina = float(stats.get("stamina", 100)),
        defense       = float(stats.get("defense", 10)),
        vision        = float(stats.get("vision", 12)),
        speed         = base_speed * sp_mod,
        agility       = float(stats.get("agility", 10)),
        luck          = float(stats.get("luck", 5)),
        willpower     = float(stats.get("willpower", 5)),
        attack_power  = float(stats.get("attack_power", hd.get("attack_power", 15))),
        preferred_range = pref_range,
        skills        = hd.get("skills", []),
    )
    # Adjust attack interval by agility
    h.attack_interval = max(0.5, 1.5 - h.agility * 0.04)
    h.stamina_regen_rate = 3.0 + h.willpower * 0.3
    return h


# ── Tick helpers ──────────────────────────────────────────────────────────────

def _tick_cooldowns(h: HeroRuntimeState, dt: float) -> None:
    for sk_id in list(h.cooldowns):
        h.cooldowns[sk_id] = max(0.0, h.cooldowns[sk_id] - dt)

def _tick_stamina(h: HeroRuntimeState, dt: float) -> None:
    if h.current_cast and h.current_cast.action_type.value == "channel":
        h.current_stamina = max(0.0, h.current_stamina - h.stamina_drain_rate * dt)
    else:
        h.current_stamina = min(
            h.max_stamina,
            h.current_stamina + h.stamina_regen_rate * dt,
        )
