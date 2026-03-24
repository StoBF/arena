"""
Tactical Battle Simulator — v1 MVP

Reads HeroOrder objects for each hero in both teams and simulates the
pre-planned combat round-by-round.

Plan-adherence probability:
  adherence_chance = clamp(hero.willpower / 20, 0.35, 1.0)
  If random() > adherence_chance → hero falls back to fallback_rule or basic_attack.

Damage formula (simplified):
  raw_dmg = strength * stance_multiplier * (1 + skill_bonus)
  effective = max(1, raw_dmg - defender_defense * 0.5)

Stamina drain per action:
  cost = 5 + stance_stamina_cost
  If stamina < 10 → hero is exhausted → forced to "rest" this round.

Willpower break (control resistance):
  control lands if attacker_willpower > defender_willpower * (1 + control_resistance_bonus)
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

STANCE_MULTIPLIERS = {
    "attack":    1.3,
    "defense":   0.7,
    "control":   0.8,
    "support":   0.6,
    "intercept": 0.9,
    "reserve":   0.5,
}

STANCE_STAMINA_COST = {
    "attack":    8,
    "defense":   4,
    "control":   10,
    "support":   6,
    "intercept": 7,
    "reserve":   2,
}

MAX_ROUNDS = 12


@dataclass
class CombatHero:
    hero_id:   int
    user_id:   int
    team:      str          # "a" or "b"
    name:      str

    # Stats
    hp:        int
    max_hp:    int
    stamina:   int
    willpower: int
    strength:  int
    agility:   int
    defense:   int

    # Order
    stance:           str = "attack"
    primary_action:   str = "basic_attack"
    primary_target:   Optional[str] = None
    fallback_rule:    Optional[str] = None
    reactive_trigger: Optional[str] = None

    alive: bool = True

    def adherence_chance(self) -> float:
        return max(0.35, min(1.0, self.willpower / 20.0))

    def is_following_plan(self) -> bool:
        return random.random() <= self.adherence_chance()

    def take_damage(self, dmg: int) -> int:
        dmg = max(1, dmg)
        self.hp = max(0, self.hp - dmg)
        if self.hp == 0:
            self.alive = False
        return dmg

    def drain_stamina(self, cost: int):
        self.stamina = max(0, self.stamina - cost)


@dataclass
class RoundEvent:
    round_num: int
    actor_id:  int
    actor_name: str
    action:    str
    target_id: Optional[int]
    target_name: Optional[str]
    damage:    int = 0
    note:      str = ""


class BattleSimulator:
    """
    Simulate a single battle between team_a and team_b.

    Parameters
    ----------
    team_a, team_b : list of CombatHero
    """

    def __init__(self, team_a: List[CombatHero], team_b: List[CombatHero]):
        self.teams: Dict[str, List[CombatHero]] = {"a": team_a, "b": team_b}
        self.log: List[RoundEvent] = []

    # ── public entry point ────────────────────────────────────────────────
    def run(self) -> Dict[str, Any]:
        for rnd in range(1, MAX_ROUNDS + 1):
            if not self._any_alive("a") or not self._any_alive("b"):
                break
            self._run_round(rnd)

        winner = self._determine_winner()
        return {
            "winner_team": winner,
            "rounds":      rnd,
            "log":         [self._event_to_dict(e) for e in self.log],
            "survivors": {
                "a": [h.hero_id for h in self.teams["a"] if h.alive],
                "b": [h.hero_id for h in self.teams["b"] if h.alive],
            },
        }

    # ── round simulation ──────────────────────────────────────────────────
    def _run_round(self, rnd: int):
        # Alternate initiative by agility jitter
        all_heroes = (
            [(h, "a") for h in self.teams["a"] if h.alive] +
            [(h, "b") for h in self.teams["b"] if h.alive]
        )
        all_heroes.sort(key=lambda x: x[0].agility + random.randint(0, 5), reverse=True)

        for hero, team in all_heroes:
            if not hero.alive:
                continue
            enemies = [h for h in self.teams[self._enemy(team)] if h.alive]
            allies  = [h for h in self.teams[team] if h.alive and h.hero_id != hero.hero_id]
            if not enemies:
                break

            event = self._act(hero, enemies, allies, rnd)
            self.log.append(event)

    def _act(self, hero: CombatHero, enemies: List[CombatHero],
             allies: List[CombatHero], rnd: int) -> RoundEvent:
        # Stamina exhaustion check
        if hero.stamina < 10:
            hero.drain_stamina(2)
            return RoundEvent(rnd, hero.hero_id, hero.name,
                              "rest", None, None, note="exhausted")

        # Drain stamina for this stance
        hero.drain_stamina(STANCE_STAMINA_COST.get(hero.stance, 5))

        # Plan adherence
        using_plan = hero.is_following_plan()
        action = hero.primary_action if using_plan else (hero.fallback_rule or "basic_attack")

        # Support/heal stance → buff weakest ally
        if hero.stance == "support" and allies:
            target = min(allies, key=lambda h: h.hp)
            heal = max(5, hero.willpower * 2)
            target.hp = min(target.max_hp, target.hp + heal)
            return RoundEvent(rnd, hero.hero_id, hero.name, "heal",
                              target.hero_id, target.name, damage=-heal,
                              note="support heal")

        # Default: attack nearest enemy
        target = self._pick_target(hero, enemies)
        mult   = STANCE_MULTIPLIERS.get(hero.stance, 1.0)
        raw    = int(hero.strength * mult * random.uniform(0.85, 1.15))
        dmg    = target.take_damage(max(1, raw - target.defense // 2))

        # Reactive trigger: intercept stance reduces incoming burst
        note = "" if using_plan else "fallback"
        if not using_plan:
            note = "fallback rule"

        return RoundEvent(rnd, hero.hero_id, hero.name, action,
                          target.hero_id, target.name, damage=dmg, note=note)

    # ── helpers ───────────────────────────────────────────────────────────
    def _pick_target(self, actor: CombatHero, enemies: List[CombatHero]) -> CombatHero:
        """Pick target: lowest-hp first (simple aggro)."""
        return min(enemies, key=lambda h: h.hp)

    def _enemy(self, team: str) -> str:
        return "b" if team == "a" else "a"

    def _any_alive(self, team: str) -> bool:
        return any(h.alive for h in self.teams[team])

    def _determine_winner(self) -> str:
        a_alive = self._any_alive("a")
        b_alive = self._any_alive("b")
        if a_alive and not b_alive:
            return "a"
        if b_alive and not a_alive:
            return "b"
        # Tiebreak: team with more surviving HP
        hp_a = sum(h.hp for h in self.teams["a"] if h.alive)
        hp_b = sum(h.hp for h in self.teams["b"] if h.alive)
        if hp_a > hp_b:
            return "a"
        if hp_b > hp_a:
            return "b"
        return "draw"

    @staticmethod
    def _event_to_dict(e: RoundEvent) -> Dict[str, Any]:
        return {
            "round":       e.round_num,
            "actor_id":    e.actor_id,
            "actor_name":  e.actor_name,
            "action":      e.action,
            "target_id":   e.target_id,
            "target_name": e.target_name,
            "damage":      e.damage,
            "note":        e.note,
        }
