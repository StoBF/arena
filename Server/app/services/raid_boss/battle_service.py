"""
Raid Battle Service — phase-aware PvE simulation + boss XP formula.

Algorithm
---------
1. Load boss template, progress, phases, participants with their heroes.
2. Compute RaidPowerFactor from hero stats.
3. Run tick-based battle: each tick heroes deal damage, boss phases trigger,
   minions spawn, arena events fire.
4. Determine outcome (victory/defeat).
5. Compute boss XP = BaseXP × RaidPowerFactor × ResistanceFactor × AntiAbuseFactor.
6. Update RaidBossProgress (level, XP, win_streak, mutations, adaptive memory).
7. Persist RaidBattleLog, RaidContribution, RaidBossHistory.
8. Return structured BattleResult.
"""
from __future__ import annotations

import math
import random
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.models.raid_v2 import (
    RaidRoom, RaidBossTemplate, RaidBossProgress, RaidBossPhase,
    RaidBossMutation, RaidBattleLog, RaidContribution,
    RaidBossHistory, RaidBossSpawn, SpawnStatus, RoomStatus, MutationTrigger,
)

# ── Constants ────────────────────────────────────────────────────────────────
TICK_RATE       = 10    # ticks per second (simulation)
MAX_TICKS       = 3000  # 5 minutes
MINION_HP       = 500
MINION_DAMAGE   = 80


# ── Data containers ──────────────────────────────────────────────────────────

@dataclass
class HeroState:
    user_id:  int
    hero_id:  int
    clan_id:  Optional[int]
    name:     str
    hp:       float
    max_hp:   float
    damage:   float
    armor:    float
    speed:    float
    level:    int
    gen:      int
    alive:    bool = True

    damage_dealt:    float = 0.0
    damage_taken:    float = 0.0
    healing_done:    float = 0.0
    control_seconds: float = 0.0
    kills:           int   = 0
    mechanic_hits:   int   = 0
    survival_ticks:  int   = 0


@dataclass
class BossState:
    template:  RaidBossTemplate
    progress:  RaidBossProgress
    phases:    List[RaidBossPhase]
    hp:        float
    max_hp:    float
    current_phase: int = 1
    minions:   List[Dict] = field(default_factory=list)


@dataclass
class BattleResult:
    outcome:       str          # "victory" | "defeat"
    total_ticks:   int
    phases_broken: int
    boss_hp_remaining_pct: float
    timeline:      List[Dict]
    contributions: List[Dict]   # per hero
    boss_xp_gained: int
    level_before:  int
    level_after:   int
    mutation_gained: Optional[str]
    summary:       Dict


# ── Main service ─────────────────────────────────────────────────────────────

class RaidBattleService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def run_battle(self, room_id: int) -> BattleResult:
        room = await self.db.get(RaidRoom, room_id)
        if not room:
            raise ValueError("Room not found")

        spawn    = await self.db.get(RaidBossSpawn, room.spawn_id)
        template = await self.db.get(RaidBossTemplate, spawn.template_id)
        progress = await self._get_progress(template.id)
        phases   = await self._get_phases(template.id)

        participants = await self._load_participants(room_id)
        if not participants:
            raise ValueError("No participants in room")

        # ── Init states ───────────────────────────────────────────────────────
        level_mult = 1.0 + (progress.current_level - template.base_level) * 0.05
        boss = BossState(
            template  = template,
            progress  = progress,
            phases    = phases,
            hp        = template.base_hp * level_mult,
            max_hp    = template.base_hp * level_mult,
        )
        heroes: List[HeroState] = participants

        # ── Run simulation ────────────────────────────────────────────────────
        timeline:     List[Dict] = []
        phases_broken = 0
        tick          = 0

        while tick < MAX_TICKS:
            tick += 1
            alive_heroes = [h for h in heroes if h.alive]
            if not alive_heroes:
                break
            if boss.hp <= 0:
                break

            # Phase check
            hp_pct = boss.hp / boss.max_hp
            new_phase = self._get_phase_number(phases, hp_pct)
            if new_phase > boss.current_phase:
                boss.current_phase = new_phase
                phases_broken += 1
                timeline.append({
                    "tick": tick, "event": "phase_change",
                    "phase": new_phase, "hp_pct": hp_pct,
                })
                # Spawn minions on phase change
                phase_def = phases[new_phase - 1]
                mods = phase_def.modifiers
                if mods.get("summon_waves") or mods.get("summon_apex_drones"):
                    wave_count = mods.get("summon_waves", 2)
                    for _ in range(wave_count * 3):
                        boss.minions.append({"hp": MINION_HP, "alive": True})

            phase_def    = phases[boss.current_phase - 1]
            phase_mods   = phase_def.modifiers
            dmg_mult     = float(phase_mods.get("damage_mult", 1.0))
            armor_mult   = float(phase_mods.get("armor_mult", 1.0))
            speed_mult   = float(phase_mods.get("speed_mult", 1.0))
            boss_regen   = float(phase_mods.get("regen", 0.0))
            heal_debuff  = float(phase_mods.get("heal_debuff", 0.0))
            absorb_kills = bool(phase_mods.get("absorb_kills", False))
            lifesteal    = float(phase_mods.get("lifesteal", 0.0))

            # Boss regen
            if boss_regen > 0:
                regen_amount = boss.max_hp * boss_regen
                boss.hp = min(boss.max_hp, boss.hp + regen_amount)

            effective_armor = template.base_armor * armor_mult
            # Add learned resistances
            resist_bonus = sum(progress.learned_resistances.values()) / max(
                len(progress.learned_resistances), 1)
            effective_armor = min(effective_armor + resist_bonus * 0.5, 0.80)

            # Heroes attack boss
            for hero in alive_heroes:
                # Minion kill check
                for m in boss.minions:
                    if m["alive"]:
                        m_dmg = hero.damage * 0.5
                        m["hp"] -= m_dmg
                        if m["hp"] <= 0:
                            m["alive"] = False
                            hero.kills += 1
                            if absorb_kills:
                                boss.hp = min(boss.max_hp,
                                              boss.hp + MINION_HP * 0.5)
                        break  # one minion per hero per tick

                # Boss damage (reduced by armor)
                raw = hero.damage * (1 + hero.level * 0.02)
                actual = raw * (1.0 - effective_armor)
                boss.hp -= actual
                hero.damage_dealt += actual

                # Lifesteal
                if lifesteal > 0:
                    boss.hp = min(boss.max_hp,
                                  boss.hp + actual * lifesteal)

                hero.survival_ticks += 1

            # Boss attacks heroes (targets weakest)
            alive_heroes.sort(key=lambda h: h.hp / h.max_hp)
            for i, hero in enumerate(alive_heroes):
                if i >= max(1, int(template.base_speed * speed_mult)):
                    break
                raw_boss_dmg = template.base_damage * dmg_mult * level_mult
                effective_dmg = raw_boss_dmg * (1.0 - hero.armor)
                hero.hp -= effective_dmg
                hero.damage_taken += effective_dmg

                # Hunter archetype: executes low HP
                if template.archetype.value == "hunter" and hero.hp / hero.max_hp < 0.20:
                    hero.hp -= raw_boss_dmg * 0.5

                if hero.hp <= 0:
                    hero.alive = False
                    progress.hero_kills += 1
                    timeline.append({
                        "tick": tick, "event": "hero_dead",
                        "hero_id": hero.hero_id,
                    })

                if boss.hp <= 0:
                    break

        # ── Outcome ───────────────────────────────────────────────────────────
        alive_heroes  = [h for h in heroes if h.alive]
        outcome       = "victory" if boss.hp <= 0 else "defeat"
        boss_hp_pct   = max(0.0, boss.hp / boss.max_hp)
        duration_sec  = tick / TICK_RATE

        # ── Contributions ─────────────────────────────────────────────────────
        contributions = self._compute_contributions(heroes)

        # ── Boss XP ───────────────────────────────────────────────────────────
        if outcome == "defeat":
            level_before = progress.current_level
            xp_gained = self._compute_boss_xp(
                template, progress, heroes, boss_hp_pct, duration_sec)
            mutation = self._apply_progression(progress, xp_gained, template)
            level_after = progress.current_level
            progress.win_streak += 1
            progress.total_wins += 1
        else:
            level_before = progress.current_level
            level_after  = progress.current_level
            xp_gained    = 0
            mutation     = None
            progress.win_streak    = 0
            progress.total_defeats += 1

        progress.updated_at = datetime.utcnow()

        # Adaptive memory update
        if outcome == "defeat" and heroes:
            # Learn from what hurt the boss most
            top_hero = max(heroes, key=lambda h: h.damage_dealt)
            self._update_adaptive_memory(progress, top_hero)

        # ── Persist ───────────────────────────────────────────────────────────
        room.outcome      = outcome
        room.total_ticks  = tick
        room.status       = RoomStatus.completed
        room.finished_at  = datetime.utcnow()

        if outcome == "victory":
            spawn.status         = SpawnStatus.defeated
            spawn.resolved_at    = datetime.utcnow()
            spawn.defeated_by_room_id = room.id

        summary = {
            "outcome":        outcome,
            "total_ticks":    tick,
            "duration_sec":   round(duration_sec, 1),
            "phases_broken":  phases_broken,
            "heroes_alive":   len(alive_heroes),
            "heroes_dead":    len([h for h in heroes if not h.alive]),
            "boss_hp_pct":    round(boss_hp_pct, 3),
            "total_damage":   sum(h.damage_dealt for h in heroes),
        }

        log = RaidBattleLog(
            room_id              = room.id,
            spawn_id             = spawn.id,
            outcome              = outcome,
            total_ticks          = tick,
            phases_broken        = phases_broken,
            boss_hp_remaining_pct = boss_hp_pct,
            timeline             = timeline[-200:],   # last 200 events
            summary              = summary,
        )
        self.db.add(log)
        await self.db.flush()

        for c in contributions:
            self.db.add(RaidContribution(
                room_id              = room.id,
                user_id              = c["user_id"],
                hero_id              = c["hero_id"],
                damage_dealt         = int(c["damage_dealt"]),
                damage_taken         = int(c["damage_taken"]),
                healing_done         = 0,
                control_seconds      = 0.0,
                mechanic_hits        = c["mechanic_hits"],
                survival_ticks       = c["survival_ticks"],
                kills                = c["kills"],
                phases_contributed   = 0,
                contribution_score   = c["score"],
                contribution_pct     = c["pct"],
                is_mvp               = c.get("is_mvp", False),
            ))

        # Boss history entry
        clan_names = list({h.clan_id for h in heroes if h.clan_id})
        self.db.add(RaidBossHistory(
            template_id     = template.id,
            spawn_id        = spawn.id,
            room_id         = room.id,
            outcome         = outcome,
            clan_names      = [str(c) for c in clan_names],
            hero_count      = len(heroes),
            duration_ticks  = tick,
            xp_gained       = xp_gained,
            level_before    = level_before,
            level_after     = level_after,
            mutation_gained = mutation,
        ))

        await self.db.commit()

        return BattleResult(
            outcome               = outcome,
            total_ticks           = tick,
            phases_broken         = phases_broken,
            boss_hp_remaining_pct = boss_hp_pct,
            timeline              = timeline,
            contributions         = contributions,
            boss_xp_gained        = xp_gained,
            level_before          = level_before,
            level_after           = level_after,
            mutation_gained       = mutation,
            summary               = summary,
        )

    # ── Internal ──────────────────────────────────────────────────────────────

    def _get_phase_number(self, phases: List[RaidBossPhase], hp_pct: float) -> int:
        current = 1
        for ph in phases:
            if hp_pct <= ph.trigger_hp_pct:
                current = ph.phase_number
        return current

    def _compute_boss_xp(
        self,
        template: RaidBossTemplate,
        progress: RaidBossProgress,
        heroes:   List[HeroState],
        boss_hp_remaining: float,
        duration_sec: float,
    ) -> int:
        # RaidPowerFactor: based on heroes' average level and gen
        avg_level = sum(h.level for h in heroes) / max(len(heroes), 1)
        avg_gen   = sum(h.gen   for h in heroes) / max(len(heroes), 1)
        raid_power = (avg_level / max(template.base_level, 1)) * (1.0 + avg_gen * 0.1)
        raid_power = max(0.5, min(raid_power, 3.0))

        # ResistanceFactor: how hard did the boss work
        hp_lost = 1.0 - boss_hp_remaining
        phases_broken_est = max(0, template.num_phases - 1) * hp_lost
        resistance = 0.8 + hp_lost * 0.7 + phases_broken_est * 0.1
        if boss_hp_remaining <= 0.10:
            resistance += 0.5   # nearly died bonus
        resistance = max(0.8, min(resistance, 2.0))

        # AntiAbuseFactor: punish trivially weak raids
        min_expected_duration = 30.0  # seconds
        if duration_sec < min_expected_duration:
            abuse_factor = duration_sec / min_expected_duration
        else:
            alive_pct = len([h for h in heroes if h.alive]) / max(len(heroes), 1)
            if alive_pct < 0.1 and hp_lost < 0.1:
                abuse_factor = 0.3   # died immediately without doing anything
            else:
                abuse_factor = 1.0
        abuse_factor = max(0.2, min(abuse_factor, 1.0))

        xp = int(template.base_xp * raid_power * resistance * abuse_factor)
        return max(1, xp)

    def _apply_progression(
        self, progress: RaidBossProgress,
        xp_gained: int, template: RaidBossTemplate,
    ) -> Optional[str]:
        progress.current_xp += xp_gained
        mutation = None

        # Level up
        while progress.current_xp >= progress.xp_to_next:
            progress.current_xp -= progress.xp_to_next
            progress.current_level += 1
            progress.xp_to_next = int(progress.xp_to_next * 1.3)

            # Rank up every 5 levels
            if progress.current_level % 5 == 0:
                progress.rank = min(progress.rank + 1, 3)

            # Mutation chance on level-up
            if random.random() < 0.30:
                mutation = self._grant_mutation(progress, MutationTrigger.level_up)

        # Win streak mutation
        if progress.win_streak > 0 and progress.win_streak % 3 == 0:
            if random.random() < 0.50:
                mutation = self._grant_mutation(progress, MutationTrigger.win_streak)

        return mutation

    def _grant_mutation(
        self, progress: RaidBossProgress, trigger: MutationTrigger
    ) -> str:
        MUTATIONS = [
            {"code": "flesh_regen",    "name": "Flesh Regeneration",
             "effect": {"type": "regen", "value": 0.015}},
            {"code": "lightning_pulse","name": "Lightning Pulse",
             "effect": {"type": "aoe_damage", "element": "electric", "value": 0.20}},
            {"code": "spike_armor",    "name": "Spiked Armor",
             "effect": {"type": "reflect_damage", "value": 0.10}},
            {"code": "enhanced_swarm", "name": "Enhanced Swarm Summon",
             "effect": {"type": "summon_bonus", "value": 2}},
            {"code": "heal_break",     "name": "Healing Disruption",
             "effect": {"type": "debuff_heal", "value": 0.35}},
            {"code": "rift_aura",      "name": "Rift Aura",
             "effect": {"type": "teleport_bonus", "value": 0.30}},
            {"code": "hunt_instinct",  "name": "Hunting Instinct",
             "effect": {"type": "execute_threshold", "value": 0.25}},
            {"code": "anti_magic",     "name": "Anti-Magic Field",
             "effect": {"type": "magic_resist", "value": 0.20}},
        ]
        m = random.choice(MUTATIONS)
        self.db.add(RaidBossMutation(
            progress_id = progress.id,
            code        = m["code"],
            name        = m["name"],
            trigger     = trigger,
            effect      = m["effect"],
            is_active   = True,
        ))
        return m["name"]

    def _update_adaptive_memory(
        self, progress: RaidBossProgress, top_hero: HeroState
    ) -> None:
        lr = dict(progress.learned_resistances)
        # Increase resistance to some damage type (simplified)
        for dmg_type in ["physical", "fire", "electric", "poison"]:
            lr[dmg_type] = min(lr.get(dmg_type, 0.0) + 0.01, 0.20)
        progress.learned_resistances = lr

    def _compute_contributions(self, heroes: List[HeroState]) -> List[Dict]:
        def _score(h: HeroState) -> float:
            return (h.damage_dealt * 1.0 + h.kills * 50 +
                    h.damage_taken * 0.3 + h.survival_ticks * 0.5)

        total_score = max(sum(_score(h) for h in heroes), 1.0)
        scores = [{"hero": h, "score": _score(h)} for h in heroes]
        scores.sort(key=lambda x: x["score"], reverse=True)

        result = []
        for i, entry in enumerate(scores):
            h     = entry["hero"]
            score = entry["score"]
            result.append({
                "user_id":       h.user_id,
                "hero_id":       h.hero_id,
                "damage_dealt":  h.damage_dealt,
                "damage_taken":  h.damage_taken,
                "healing_done":  h.healing_done,
                "survival_ticks":h.survival_ticks,
                "kills":         h.kills,
                "mechanic_hits": h.mechanic_hits,
                "score":         score,
                "pct":           score / total_score,
                "is_mvp":        i == 0,
            })
        return result

    # ── DB helpers ────────────────────────────────────────────────────────────

    async def _get_progress(self, template_id: int) -> RaidBossProgress:
        result = await self.db.execute(
            select(RaidBossProgress).where(
                RaidBossProgress.template_id == template_id
            )
        )
        prog = result.scalar_one_or_none()
        if not prog:
            prog = RaidBossProgress(template_id=template_id)
            self.db.add(prog)
            await self.db.flush()
        return prog

    async def _get_phases(self, template_id: int) -> List[RaidBossPhase]:
        result = await self.db.execute(
            select(RaidBossPhase)
            .where(RaidBossPhase.template_id == template_id)
            .order_by(RaidBossPhase.phase_number)
        )
        phases = list(result.scalars().all())
        if not phases:
            raise ValueError("No phases defined for this boss")
        return phases

    async def _load_participants(self, room_id: int) -> List[HeroState]:
        from app.database.models.raid_v2 import RaidParticipant
        from app.database.models.hero import Hero  # existing hero model

        result = await self.db.execute(
            select(RaidParticipant).where(RaidParticipant.room_id == room_id)
        )
        participants = list(result.scalars().all())
        heroes: List[HeroState] = []
        for p in participants:
            hero = await self.db.get(Hero, p.hero_id)
            if not hero:
                continue
            hp = float(getattr(hero, "hp", 3000))
            heroes.append(HeroState(
                user_id  = p.user_id,
                hero_id  = p.hero_id,
                clan_id  = p.clan_id,
                name     = getattr(hero, "name", f"Hero#{p.hero_id}"),
                hp       = hp,
                max_hp   = hp,
                damage   = float(getattr(hero, "attack", 300)),
                armor    = float(getattr(hero, "defense", 0.0)) / 100.0,
                speed    = float(getattr(hero, "speed",  1.0)),
                level    = int(getattr(hero, "level",    1)),
                gen      = int(getattr(hero, "gen",      1)),
            ))
        return heroes
