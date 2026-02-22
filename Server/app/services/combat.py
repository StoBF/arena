from datetime import datetime, timedelta
from typing import List, Dict, Any, Optional
from app.database.models.hero import Hero
from app.database.models.perk import Perk
from app.services.hero import HeroService
import random
from sqlalchemy import select
from sqlalchemy.orm import joinedload

RECOVERY_TIME_MINUTES = 60  # 1 година на відновлення

# Мапа ефектів перків (приклад)
PERK_EFFECTS = {
    "Plasma Gunner": {"type": "offensive", "stat": "strength"},
    "Meteoric Defender": {"type": "defensive", "stat": "defense"},
    "Radiation Healer": {"type": "support", "stat": "health"},
    "Nebula Trickster": {"type": "utility", "stat": "agility"},
    # ... додати інші перки за потреби
}

class BattleResult:
    def __init__(self, winner: str, log: List[str], rewards: Dict[str, Any], team_a_remaining, team_b_remaining):
        self.winner = winner
        self.log = log
        self.rewards = rewards
        self.team_a_remaining = team_a_remaining
        self.team_b_remaining = team_b_remaining

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
        # Ініціалізація бою
        fighters = []
        log = []
        # Eager-load heroes with perks and equipment
        hero_ids = [h.id for h in team_a + team_b]
        result = await self.db.execute(
            select(Hero).options(
                joinedload(Hero.perks),
                joinedload(Hero.equipment_items)
            ).where(Hero.id.in_(hero_ids))
        )
        loaded_heroes = {h.id: h for h in result.scalars().all()}
        # Підготовка бійців: застосування бонусів від перків
        for hero in team_a + team_b:
            h = loaded_heroes.get(hero.id, hero)
            stats = await self.apply_perk_effects(h)
            fighters.append({
                "hero": h,
                "stats": stats,
                "current_hp": stats["health"],
                "is_dead": False
            })
        # Визначення порядку ходів
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
                # Визначаємо ціль
                if fighter["hero"] in team_a:
                    targets = [f for f in alive_b if not f["is_dead"]]
                else:
                    targets = [f for f in alive_a if not f["is_dead"]]
                if not targets:
                    continue
                target = min(targets, key=lambda t: t["current_hp"])  # ціль з найменшим HP
                # Розрахунок атаки
                dmg, is_crit, is_miss = self.calculate_damage(fighter, target)
                if is_miss:
                    log.append(f"{fighter['hero'].name} misses {target['hero'].name}!")
                    continue
                target["current_hp"] -= dmg
                log.append(f"{fighter['hero'].name} hits {target['hero'].name} for {dmg}{' (CRIT)' if is_crit else ''}.")
                if target["current_hp"] <= 0 and not target["is_dead"]:
                    target["is_dead"] = True
                    log.append(f"{target['hero'].name} is defeated!")
            round_num += 1
        # Визначення переможця
        alive_a = [f for f in fighters if f["hero"] in team_a and not f["is_dead"]]
        alive_b = [f for f in fighters if f["hero"] in team_b and not f["is_dead"]]
        if alive_a and not alive_b:
            winner = "team_a"
        elif alive_b and not alive_a:
            winner = "team_b"
        else:
            winner = "draw"
        # Оновлення статусу героїв
        now = datetime.utcnow()
        for f in fighters:
            hero = f["hero"]
            if f["is_dead"]:
                hero.is_dead = True
                hero.dead_until = now + timedelta(minutes=RECOVERY_TIME_MINUTES)
            else:
                hero.is_dead = False
                hero.dead_until = None
            await self.db.commit()
        # Нагороди (спрощено)
        rewards = {"xp": 100 if winner == "team_a" else 50}
        return BattleResult(winner, log, rewards, [f["hero"].id for f in alive_a], [f["hero"].id for f in alive_b])

    async def apply_perk_effects(self, hero: Hero) -> Dict[str, int]:
        # Base stats
        stats = {
            "strength": hero.strength,
            "agility": hero.agility,
            "intelligence": hero.intelligence,
            "endurance": hero.endurance,
            "speed": hero.speed,
            "health": hero.health,
            "defense": hero.defense,
            "luck": hero.luck,
            "field_of_view": hero.field_of_view,
        }
        # Apply perk modifiers
        for hp in getattr(hero, "perks", []):
            if hp.perk and hp.perk.modifiers:
                for stat, val in hp.perk.modifiers.items():
                    if stat in stats:
                        stats[stat] += int(val) * hp.perk_level
            elif hp.perk_name:
                effect = PERK_EFFECTS.get(hp.perk_name)
                if effect:
                    stat_name = effect.get("stat")
                    if stat_name in stats:
                        stats[stat_name] += hp.perk_level
        return stats

    def calculate_damage(self, attacker, defender):
        atk = attacker["stats"]["strength"]
        defense = defender["stats"]["defense"]
        luck = attacker["stats"]["luck"]
        dodge = defender["stats"]["luck"]
        # Крит/ухилення
        is_crit = random.random() < (luck / 100)
        is_miss = random.random() < (dodge / 150)
        base_dmg = max(1, atk - int(defense * 0.7))
        if is_crit:
            base_dmg *= 2
        if is_miss:
            base_dmg = 0
        return base_dmg, is_crit, is_miss 