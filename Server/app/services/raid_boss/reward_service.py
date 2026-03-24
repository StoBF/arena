"""
Raid Reward Service — 3-tier loot: guaranteed base, chance-based core, ultra-rare.
"""
from __future__ import annotations

import random
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.models.raid_v2 import (
    RaidBossTemplate, RaidBossProgress, RaidBossSpawn,
    RaidDropEntry, RaidRewardRoll, RaidBattleLog,
    DropOwnership, DropRarity,
)


# ── Condition evaluators ──────────────────────────────────────────────────────

def _eval_condition(cond: Dict, ctx: Dict) -> float:
    """Return bonus chance from a bonus_condition if satisfied."""
    ctype = cond.get("condition", "")
    val   = cond.get("value")
    bonus = float(cond.get("bonus", 0.0))
    if ctype == "boss_level_gte" and ctx.get("boss_level", 1) >= int(val):
        return bonus
    if ctype == "no_deaths"     and ctx.get("no_deaths",   False) == bool(val):
        return bonus
    if ctype == "full_coalition" and ctx.get("full_coalition", False) == bool(val):
        return bonus
    if ctype == "all_clans_present" and ctx.get("all_clans_present", False):
        return bonus
    return 0.0


def _adjusted_chance(entry: RaidDropEntry, ctx: Dict) -> float:
    base  = entry.base_chance
    bonus = sum(_eval_condition(c, ctx) for c in (entry.bonus_conditions or []))
    return min(base + bonus, 1.0)


# ── Main service ──────────────────────────────────────────────────────────────

class RaidRewardService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def distribute(
        self,
        room_id:      int,
        battle_log:   RaidBattleLog,
        contributions: List[Dict],   # from battle_service
        ctx:          Optional[Dict] = None,
    ) -> List[RaidRewardRoll]:
        """
        Roll all rewards after a raid victory and persist them.
        ctx: optional context for condition evaluation (boss_level, no_deaths, …)
        """
        ctx = ctx or {}

        spawn    = await self.db.get(RaidBossSpawn, battle_log.spawn_id)
        template = await self.db.get(RaidBossTemplate, spawn.template_id)
        progress = await self._get_progress(template.id)

        # Enrich context
        ctx.setdefault("boss_level", progress.current_level)

        # Load drop table
        result = await self.db.execute(
            select(RaidDropEntry).where(RaidDropEntry.template_id == template.id)
        )
        entries: List[RaidDropEntry] = list(result.scalars().all())

        # Sort by drop_group
        guaranteed  = [e for e in entries if e.is_guaranteed]
        core_drops  = [e for e in entries if not e.is_guaranteed
                       and e.drop_group != "ultra_rare"]
        ultra_rare  = [e for e in entries if not e.is_guaranteed
                       and e.drop_group == "ultra_rare"]

        rolls: List[RaidRewardRoll] = []

        # Contribution lookup (for weighted rolls)
        contrib_by_hero = {c["hero_id"]: c for c in contributions}

        # ── Tier 1: Guaranteed base rewards (per player) ──────────────────────
        for entry in guaranteed:
            for c in contributions:
                qty = random.randint(entry.min_qty, entry.max_qty)
                rolls.append(self._make_roll(
                    battle_log_id = battle_log.id,
                    entry         = entry,
                    user_id       = c["user_id"],
                    quantity      = qty,
                    rolled_chance = 1.0,
                ))

        # ── Tier 2: Chance-based core drops ──────────────────────────────────
        for entry in core_drops:
            chance = _adjusted_chance(entry, ctx)
            if entry.ownership == DropOwnership.personal:
                # Each participant rolls independently
                for c in contributions:
                    contrib_factor = min(1.0 + c.get("pct", 0) * 0.5, 1.5)
                    if random.random() < chance * contrib_factor:
                        qty = random.randint(entry.min_qty, entry.max_qty)
                        rolls.append(self._make_roll(
                            battle_log_id = battle_log.id,
                            entry         = entry,
                            user_id       = c["user_id"],
                            quantity      = qty,
                            rolled_chance = chance,
                        ))
            elif entry.ownership == DropOwnership.clan:
                # One roll per unique clan
                clan_ids = list({c.get("clan_id") for c in contributions
                                 if c.get("clan_id")})
                for cid in clan_ids:
                    if random.random() < chance:
                        qty = random.randint(entry.min_qty, entry.max_qty)
                        rolls.append(self._make_roll(
                            battle_log_id = battle_log.id,
                            entry         = entry,
                            clan_id       = cid,
                            quantity      = qty,
                            rolled_chance = chance,
                        ))
            else:
                # Coalition / single roll
                if random.random() < chance:
                    qty = random.randint(entry.min_qty, entry.max_qty)
                    rolls.append(self._make_roll(
                        battle_log_id = battle_log.id,
                        entry         = entry,
                        quantity      = qty,
                        rolled_chance = chance,
                    ))

        # ── Tier 3: Ultra-rare (weighted roll among contributors) ─────────────
        for entry in ultra_rare:
            chance = _adjusted_chance(entry, ctx)
            # Single roll for the whole raid
            if random.random() < chance:
                # Weighted selection: higher contribution = higher chance
                if entry.ownership == DropOwnership.weighted and contributions:
                    total_score = max(sum(c.get("score", 1) for c in contributions), 1)
                    weights     = [max(c.get("score", 1), 0.01) / total_score
                                   for c in contributions]
                    winner      = random.choices(contributions, weights=weights, k=1)[0]
                    rolls.append(self._make_roll(
                        battle_log_id = battle_log.id,
                        entry         = entry,
                        user_id       = winner["user_id"],
                        quantity      = 1,
                        rolled_chance = chance,
                        is_ultra_rare = True,
                    ))
                else:
                    rolls.append(self._make_roll(
                        battle_log_id = battle_log.id,
                        entry         = entry,
                        quantity      = 1,
                        rolled_chance = chance,
                        is_ultra_rare = True,
                    ))

        for r in rolls:
            self.db.add(r)
        await self.db.commit()
        return rolls

    # ── Helpers ───────────────────────────────────────────────────────────────

    def _make_roll(
        self,
        battle_log_id: int,
        entry:         RaidDropEntry,
        user_id:       Optional[int] = None,
        clan_id:       Optional[int] = None,
        quantity:      int = 1,
        rolled_chance: float = 0.0,
        is_ultra_rare: bool = False,
    ) -> RaidRewardRoll:
        return RaidRewardRoll(
            battle_log_id = battle_log_id,
            user_id       = user_id,
            clan_id       = clan_id,
            drop_entry_id = entry.id,
            item_code     = entry.item_code,
            recipe_code   = entry.recipe_code,
            artifact_code = entry.artifact_code,
            display_name  = entry.display_name,
            quantity      = quantity,
            rarity        = entry.rarity,
            ownership     = entry.ownership,
            rolled_chance = rolled_chance,
            is_ultra_rare = is_ultra_rare,
            granted_at    = datetime.utcnow(),
        )

    async def _get_progress(self, template_id: int) -> RaidBossProgress:
        from app.database.models.raid_v2 import RaidBossProgress
        result = await self.db.execute(
            select(RaidBossProgress).where(
                RaidBossProgress.template_id == template_id
            )
        )
        prog = result.scalar_one_or_none()
        if not prog:
            from app.database.models.raid_v2 import RaidBossTemplate
            t = await self.db.get(RaidBossTemplate, template_id)
            prog = RaidBossProgress(
                template_id   = template_id,
                current_level = t.base_level if t else 1,
            )
            self.db.add(prog)
            await self.db.flush()
        return prog

    async def get_loot_preview(
        self,
        template_id: int,
        boss_level:  int = 1,
        no_deaths:   bool = False,
    ) -> List[Dict]:
        """Return full loot table with adjusted chances for UI preview."""
        result = await self.db.execute(
            select(RaidDropEntry).where(RaidDropEntry.template_id == template_id)
        )
        entries = list(result.scalars().all())
        ctx = {"boss_level": boss_level, "no_deaths": no_deaths}

        out = []
        for e in entries:
            adj = _adjusted_chance(e, ctx)
            out.append({
                "display_name":       e.display_name,
                "rarity":             e.rarity.value,
                "ownership":          e.ownership.value,
                "drop_group":         e.drop_group,
                "base_chance":        round(e.base_chance * 100, 2),
                "adjusted_chance":    round(adj * 100, 2),
                "min_qty":            e.min_qty,
                "max_qty":            e.max_qty,
                "is_guaranteed":      e.is_guaranteed,
                "bonus_conditions":   e.bonus_conditions,
                "item_code":          e.item_code,
                "recipe_code":        e.recipe_code,
                "artifact_code":      e.artifact_code,
            })
        return out
