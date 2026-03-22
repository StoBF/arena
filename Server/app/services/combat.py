"""
Combat service — v2

Uses hero.stats (HeroStats) for all stat references.
No perks/perk-trees — skill catalog drives combat in future iterations.
Equipment bonuses read via item_stat_map (v1-column → v2-stat mapping).

RNG is deterministic (seeded) for reproducibility, matching actions.py.
"""
from datetime import datetime
from typing import List, Dict, Any, Optional

import hashlib
import random

from sqlalchemy import select
from sqlalchemy.orm import joinedload

from app.database.models.hero import Hero, HeroStats
from app.core.item_stat_map import equipment_stat_totals


RECOVERY_TIME_MINUTES = 60


class BattleResult:
    def __init__(
        self,
        winner: str,
        log: List[str],
        rewards: Dict[str, Any],
        team_a_remaining: List[int],
        team_b_remaining: List[int],
    ):
        self.winner = winner
        self.log = log
        self.rewards = rewards
        self.team_a_remaining = team_a_remaining
        self.team_b_remaining = team_b_remaining


# ── Deterministic RNG seed (same algorithm as actions.py) ─────────

def _make_seed(*parts: Any) -> int:
    raw = "|".join(str(p) for p in parts)
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _hero_stats(hero: Hero) -> Dict[str, int]:
    """Extract combat-relevant stats from v2 HeroStats relationship."""
    s: Optional[HeroStats] = getattr(hero, "stats", None)
    if s is None:
        return {
            "health": 100,
            "stamina": 100,
            "defense": 10,
            "speed": 10,
            "agility": 10,
            "luck": 5,
            "willpower": 5,
            "vision": 10,
        }
    return {
        "health": s.health,
        "stamina": s.stamina,
        "defense": s.defense,
        "speed": s.speed,
        "agility": s.agility,
        "luck": s.luck,
        "willpower": s.willpower,
        "vision": s.vision,
    }


def _equipment_bonus(hero: Hero) -> Dict[str, int]:
    """Return v2-keyed equipment bonus totals for a hero."""
    return equipment_stat_totals(getattr(hero, "equipment_items", []))


class CombatService:
    def __init__(self, db_session):
        self.db = db_session

    async def simulate_duel(self, hero1: Hero, hero2: Hero) -> BattleResult:
        return await self.simulate_battle([hero1], [hero2])

    async def simulate_team_battle(self, team_a: List[Hero], team_b: List[Hero]) -> BattleResult:
        return await self.simulate_battle(team_a, team_b)

    async def simulate_raid(self, team: List[Hero], boss: Hero) -> BattleResult:
        return await self.simulate_battle(team, [boss])

    async def simulate_battle(self, team_a: List[Hero], team_b: List[Hero]) -> BattleResult:
        # Eager-load heroes with stats + equipment
        hero_ids = [h.id for h in team_a + team_b]
        result = await self.db.execute(
            select(Hero).options(
                joinedload(Hero.stats),
                joinedload(Hero.equipment_items),
            ).where(Hero.id.in_(hero_ids))
        )
        loaded_heroes = {h.id: h for h in result.scalars().unique().all()}

        fighters: List[Dict[str, Any]] = []
        log: List[str] = []

        for hero in team_a + team_b:
            h = loaded_heroes.get(hero.id, hero)
            stats = _hero_stats(h)
            # Apply equipment bonuses (v2-keyed)
            eq_bonuses = _equipment_bonus(h)
            for stat_key in stats:
                stats[stat_key] += eq_bonuses.get(stat_key, 0)
            fighters.append({
                "hero": h,
                "stats": stats,
                "current_hp": stats["health"],
                "is_dead": False,
            })

        # Deterministic seed from participant IDs
        seed = _make_seed("combat", *(f["hero"].id for f in fighters))
        rng = random.Random(seed)

        # Turn order by speed
        fighters = sorted(fighters, key=lambda f: f["stats"]["speed"], reverse=True)

        round_num = 1
        while True:
            alive_a = [f for f in fighters if f["hero"] in team_a and not f["is_dead"]]
            alive_b = [f for f in fighters if f["hero"] in team_b and not f["is_dead"]]
            if not alive_a or not alive_b:
                break
            log.append(f"--- Round {round_num} ---")
            for fighter in fighters:
                if fighter["is_dead"]:
                    continue
                if fighter["hero"] in team_a:
                    targets = [f for f in fighters if f["hero"] in team_b and not f["is_dead"]]
                else:
                    targets = [f for f in fighters if f["hero"] in team_a and not f["is_dead"]]
                if not targets:
                    continue
                target = min(targets, key=lambda t: t["current_hp"])
                dmg, is_crit, is_miss = self._calculate_damage(fighter, target, rng)
                if is_miss:
                    log.append(f"{fighter['hero'].name} misses {target['hero'].name}!")
                    continue
                target["current_hp"] -= dmg
                log.append(
                    f"{fighter['hero'].name} hits {target['hero'].name} for {dmg}"
                    f"{' (CRIT)' if is_crit else ''}."
                )
                if target["current_hp"] <= 0 and not target["is_dead"]:
                    target["is_dead"] = True
                    log.append(f"{target['hero'].name} is defeated!")
            round_num += 1

        alive_a = [f for f in fighters if f["hero"] in team_a and not f["is_dead"]]
        alive_b = [f for f in fighters if f["hero"] in team_b and not f["is_dead"]]
        if alive_a and not alive_b:
            winner = "team_a"
        elif alive_b and not alive_a:
            winner = "team_b"
        else:
            winner = "draw"

        # Update hero condition — single atomic commit
        now = datetime.utcnow()
        for f in fighters:
            hero = f["hero"]
            if f["is_dead"]:
                hero.is_dead = True
                hero.dead_at = now
            else:
                hero.is_dead = False
                hero.dead_at = None
        await self.db.commit()

        rewards: Dict[str, Any] = {}
        return BattleResult(
            winner,
            log,
            rewards,
            [f["hero"].id for f in alive_a],
            [f["hero"].id for f in alive_b],
        )

    @staticmethod
    def _calculate_damage(
        attacker: Dict, defender: Dict, rng: random.Random
    ) -> tuple:
        """Deterministic damage using seeded RNG and v2 stats."""
        atk_stats = attacker["stats"]
        def_stats = defender["stats"]

        attack_power = atk_stats["stamina"] * 1.2 + atk_stats["willpower"] * 0.3
        defense_val = def_stats["defense"]

        luck_atk = atk_stats["luck"]
        luck_def = def_stats["luck"]

        is_crit = rng.random() < (luck_atk / 100)
        is_miss = rng.random() < (luck_def / 150)

        base_dmg = max(1, int(attack_power - defense_val * 0.7))
        if is_crit:
            base_dmg *= 2
        if is_miss:
            base_dmg = 0
        return base_dmg, is_crit, is_miss
