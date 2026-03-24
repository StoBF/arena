"""
Reward Distributor — distributes currency, resources, and special items to
participants after any type of battle.

Supported modes
---------------
distribute_pvp(winner_team, team_a_ids, team_b_ids)
    → Standard 5v5 or 1v1 PvP; winner gets WIN_MULT, loser LOSS_MULT.

distribute_raid(user_ids, boss_tier, success, hero_results?)
    → PvE raid boss fight; scales with boss_tier; drops RaidTicket on success.

distribute_pve(user_ids, difficulty, success, hero_results?)
    → PvE dungeon / arena run; lighter drops than raid.

distribute_live_battle(winner_team, team_a_ids, team_b_ids, hero_results)
    → Real-time 5v5 MOBA battle; contribution-scaled bonus on top of base.

All helpers persist to:
  - User.balance (currency)
  - PlayerResourceInventory (resource stacks, upsert)
  - RaidTicket (raid/live-battle ticket drops)

Contribution scaling (all modes that accept hero_results):
  Each player's reward is multiplied by a contribution factor:
    factor = 0.85 + 0.30 * (own_score / team_avg_score)   clamped [0.70, 1.40]
  score = damage_dealt * 1.0 + kills * 50 + control_seconds * 5
"""
from __future__ import annotations

import random
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert as pg_insert

from app.database.models.battle_room import PlayerResourceInventory
from app.database.models.resource import GameResource, ResourceCategory
from app.database.models.clan import RaidTicket, TicketOwnerType

# ── Constants ─────────────────────────────────────────────────────────────────

BASE_CURRENCY_PER_PLAYER = 50

# Multipliers per outcome
WIN_MULT  = 3.0
LOSS_MULT = 0.5
DRAW_MULT = 1.2

# Extra resource rolls for winners
_WIN_ROLL_BONUS = 2

# Category roll counts and drop chances
_PVP_ROLLS: Dict[str, int] = {
    "basic": 4, "structural": 2, "energetic": 1, "bio": 1,
}
_RAID_ROLLS: Dict[str, int] = {
    "basic": 5, "structural": 3, "energetic": 2, "bio": 2, "raid_rare": 1,
}
_PVE_ROLLS: Dict[str, int] = {
    "basic": 3, "structural": 2, "energetic": 1, "bio": 1,
}

_DROP_CHANCE: Dict[str, float] = {
    "basic": 0.70, "structural": 0.45, "energetic": 0.25,
    "bio": 0.20, "raid_rare": 0.08, "intermediate": 0.0,
}

# Ticket drop chances by boss tier
def _ticket_chance(boss_tier: int) -> float:
    return min(0.25 + 0.05 * (boss_tier - 1), 0.70)


# ── Main class ────────────────────────────────────────────────────────────────

class RewardDistributor:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ── PvP ───────────────────────────────────────────────────────────────────

    async def distribute_pvp(
        self,
        winner_team: str,           # "a" | "b" | "draw"
        team_a_ids:  List[int],
        team_b_ids:  List[int],
        hero_results: Optional[Dict[int, Dict[str, Any]]] = None,
    ) -> Dict[int, Dict[str, Any]]:
        """
        Standard PvP reward. Optional hero_results enables contribution scaling.
        hero_results: {user_id: {damage_dealt, kills, control_seconds}}
        """
        resources = await self._load_lootable_resources()
        results: Dict[int, Dict[str, Any]] = {}

        for user_id in team_a_ids:
            mult  = WIN_MULT if winner_team == "a" else (DRAW_MULT if winner_team == "draw" else LOSS_MULT)
            bonus = _WIN_ROLL_BONUS if winner_team == "a" else 0
            factor = _contribution_factor(user_id, team_a_ids, hero_results)
            results[user_id] = await self._build_reward(
                user_id, mult * factor, bonus, resources, _PVP_ROLLS)

        for user_id in team_b_ids:
            mult  = WIN_MULT if winner_team == "b" else (DRAW_MULT if winner_team == "draw" else LOSS_MULT)
            bonus = _WIN_ROLL_BONUS if winner_team == "b" else 0
            factor = _contribution_factor(user_id, team_b_ids, hero_results)
            results[user_id] = await self._build_reward(
                user_id, mult * factor, bonus, resources, _PVP_ROLLS)

        await self._persist_rewards(results)
        return results

    # ── Raid ──────────────────────────────────────────────────────────────────

    async def distribute_raid(
        self,
        user_ids:     List[int],
        boss_tier:    int = 1,
        success:      bool = True,
        hero_results: Optional[Dict[int, Dict[str, Any]]] = None,
    ) -> Dict[int, Dict[str, Any]]:
        """
        Raid boss reward. Scales with boss_tier.
        Drops RaidTicket with probability based on tier.
        """
        resources     = await self._load_lootable_resources()
        base_mult     = (WIN_MULT + boss_tier * 0.5) if success else LOSS_MULT
        extra_rolls   = boss_tier if success else 0
        ticket_prob   = _ticket_chance(boss_tier) if success else 0.0

        results: Dict[int, Dict[str, Any]] = {}
        for user_id in user_ids:
            factor = _contribution_factor(user_id, user_ids, hero_results)
            reward = await self._build_reward(
                user_id, base_mult * factor, extra_rolls, resources, _RAID_ROLLS)
            if random.random() < ticket_prob:
                reward["raid_ticket"] = {"boss_tier": boss_tier, "ticket_type": "standard"}
            results[user_id] = reward

        await self._persist_rewards(results)
        return results

    # ── PvE ───────────────────────────────────────────────────────────────────

    async def distribute_pve(
        self,
        user_ids:   List[int],
        difficulty: int  = 1,        # 1–5
        success:    bool = True,
        hero_results: Optional[Dict[int, Dict[str, Any]]] = None,
    ) -> Dict[int, Dict[str, Any]]:
        """
        PvE dungeon / arena run. Lighter than raid but scales with difficulty.
        """
        resources   = await self._load_lootable_resources()
        base_mult   = (1.5 + difficulty * 0.3) if success else LOSS_MULT
        extra_rolls = (difficulty // 2) if success else 0

        results: Dict[int, Dict[str, Any]] = {}
        for user_id in user_ids:
            factor = _contribution_factor(user_id, user_ids, hero_results)
            results[user_id] = await self._build_reward(
                user_id, base_mult * factor, extra_rolls, resources, _PVE_ROLLS)

        await self._persist_rewards(results)
        return results

    # ── Live Battle (real-time 5v5 MOBA) ─────────────────────────────────────

    async def distribute_live_battle(
        self,
        winner_team:  str,                # "A" | "B" | "draw"
        team_a_user_ids: List[int],
        team_b_user_ids: List[int],
        hero_results: Dict[int, Dict[str, Any]],
        # hero_results: {user_id: {damage_dealt, kills, control_seconds, survived}}
        boss_tier:    int = 0,            # 0 = regular battle, >0 = ranked/tournament
    ) -> Dict[int, Dict[str, Any]]:
        """
        Real-time 5v5 MOBA battle reward.
        Contribution scaling is mandatory here (hero_results required).
        Survivors on winning team get a ticket if boss_tier >= 1.
        """
        resources = await self._load_lootable_resources()
        results: Dict[int, Dict[str, Any]] = {}

        for user_id in team_a_user_ids:
            mult  = WIN_MULT if winner_team == "A" else (DRAW_MULT if winner_team == "draw" else LOSS_MULT)
            bonus = _WIN_ROLL_BONUS if winner_team == "A" else 0
            factor = _contribution_factor(user_id, team_a_user_ids, hero_results)
            reward = await self._build_reward(
                user_id, mult * factor, bonus, resources, _PVP_ROLLS)
            # Ticket drop for ranked battles
            if boss_tier >= 1 and winner_team == "A":
                hr = (hero_results or {}).get(user_id, {})
                if hr.get("survived", False) and random.random() < _ticket_chance(boss_tier):
                    reward["raid_ticket"] = {"boss_tier": boss_tier, "ticket_type": "ranked"}
            results[user_id] = reward

        for user_id in team_b_user_ids:
            mult  = WIN_MULT if winner_team == "B" else (DRAW_MULT if winner_team == "draw" else LOSS_MULT)
            bonus = _WIN_ROLL_BONUS if winner_team == "B" else 0
            factor = _contribution_factor(user_id, team_b_user_ids, hero_results)
            reward = await self._build_reward(
                user_id, mult * factor, bonus, resources, _PVP_ROLLS)
            if boss_tier >= 1 and winner_team == "B":
                hr = (hero_results or {}).get(user_id, {})
                if hr.get("survived", False) and random.random() < _ticket_chance(boss_tier):
                    reward["raid_ticket"] = {"boss_tier": boss_tier, "ticket_type": "ranked"}
            results[user_id] = reward

        await self._persist_rewards(results)
        return results

    # ── Internal ──────────────────────────────────────────────────────────────

    async def _build_reward(
        self,
        user_id:       int,
        currency_mult: float,
        extra_rolls:   int,
        resources:     List[GameResource],
        roll_table:    Dict[str, int],
    ) -> Dict[str, Any]:
        currency = max(1, int(BASE_CURRENCY_PER_PLAYER * currency_mult))
        dropped: List[Dict[str, Any]] = []

        by_cat: Dict[str, List[GameResource]] = {}
        for r in resources:
            cat = r.category.value if hasattr(r.category, "value") else str(r.category)
            by_cat.setdefault(cat, []).append(r)

        for cat, rolls in roll_table.items():
            pool   = by_cat.get(cat, [])
            chance = _DROP_CHANCE.get(cat, 0.0)
            if not pool or chance <= 0.0:
                continue
            for _ in range(rolls + extra_rolls):
                if random.random() < chance:
                    pick = random.choice(pool)
                    qty  = random.randint(1, 3 + extra_rolls)
                    dropped.append({
                        "resource_id": pick.id,
                        "code":        pick.code,
                        "quantity":    qty,
                    })

        return {"user_id": user_id, "currency": currency, "resources": dropped}

    async def _load_lootable_resources(self) -> List[GameResource]:
        result = await self.db.execute(
            select(GameResource).where(
                GameResource.category.in_([
                    ResourceCategory.basic.value,
                    ResourceCategory.structural.value,
                    ResourceCategory.energetic.value,
                    ResourceCategory.bio.value,
                ])
            )
        )
        return list(result.scalars().all())

    async def _persist_rewards(self, results: Dict[int, Dict[str, Any]]) -> None:
        from app.database.models.user import User

        for user_id, reward in results.items():
            # ── Currency ──────────────────────────────────────────────
            user = await self.db.get(User, user_id)
            if user:
                user.balance = float(user.balance or 0) + reward["currency"]

            # ── Resources (upsert) ────────────────────────────────────
            for item in reward.get("resources", []):
                stmt = (
                    pg_insert(PlayerResourceInventory)
                    .values(user_id=user_id,
                            resource_id=item["resource_id"],
                            quantity=item["quantity"])
                    .on_conflict_do_update(
                        index_elements=["user_id", "resource_id"],
                        set_={"quantity": PlayerResourceInventory.quantity + item["quantity"]},
                    )
                )
                await self.db.execute(stmt)

            # ── Raid / ranked ticket ──────────────────────────────────
            ticket_info = reward.get("raid_ticket")
            if ticket_info:
                self.db.add(RaidTicket(
                    owner_type    = TicketOwnerType.user,
                    owner_user_id = user_id,
                    ticket_type   = ticket_info.get("ticket_type", "standard"),
                    boss_tier     = ticket_info.get("boss_tier", 1),
                    tradable      = True,
                    created_at    = datetime.utcnow(),
                ))

        await self.db.commit()


# ── Contribution scaling helper ───────────────────────────────────────────────

def _contribution_factor(
    user_id:      int,
    team_ids:     List[int],
    hero_results: Optional[Dict[int, Dict[str, Any]]],
) -> float:
    """
    Returns a multiplier [0.70, 1.40] based on this player's contribution
    relative to their team's average.  Returns 1.0 if no data available.
    """
    if not hero_results or user_id not in hero_results:
        return 1.0

    def _score(hr: Dict[str, Any]) -> float:
        return (
            float(hr.get("damage_dealt",    0)) * 1.0 +
            float(hr.get("kills",           0)) * 50.0 +
            float(hr.get("control_seconds", 0)) * 5.0
        )

    team_scores = [_score(hero_results[uid]) for uid in team_ids if uid in hero_results]
    if not team_scores:
        return 1.0

    avg   = sum(team_scores) / len(team_scores)
    own   = _score(hero_results[user_id])
    if avg < 1.0:
        return 1.0

    factor = 0.85 + 0.30 * (own / avg)
    return max(0.70, min(factor, 1.40))
