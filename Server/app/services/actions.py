from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import hashlib
import random
from typing import Any, Dict, List, Optional, Tuple

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database.models.hero import Hero, HeroPerk
from app.database.models.models import Equipment


MAX_ROUNDS: int = 100
TEAM_SIZE: int = 3


@dataclass
class FighterState:
    entity: Any
    owner_id: Optional[int]
    entity_id: int
    team: str
    max_hp: int
    current_hp: int
    stats: Dict[str, float]

    @property
    def alive(self) -> bool:
        return self.current_hp > 0


def _to_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except Exception:
        return default


def _to_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except Exception:
        return default


def _entity_id(entity: Any, fallback: int = 0) -> int:
    if isinstance(entity, dict):
        return _to_int(entity.get("id", entity.get("template_id", fallback)), fallback)
    if isinstance(entity, int):
        return entity
    return _to_int(getattr(entity, "id", fallback), fallback)


def _get_stat(entity: Any, key: str, default: int = 0) -> int:
    if isinstance(entity, dict):
        if key in entity:
            return _to_int(entity.get(key), default)
        base_stats = entity.get("stats") or entity.get("base_stats")
        if isinstance(base_stats, dict):
            if key in base_stats:
                return _to_int(base_stats.get(key), default)
            if key == "vitality":
                return _to_int(base_stats.get("endurance", default), default)
            if key == "agility":
                return _to_int(base_stats.get("speed", default), default)
            if key == "strength":
                return _to_int(base_stats.get("power", default), default)
        if key == "level":
            return _to_int(entity.get("level", 1), 1)
        if key == "vitality":
            return _to_int(entity.get("endurance", default), default)
        if key == "agility":
            return _to_int(entity.get("speed", default), default)
        if key == "strength":
            return _to_int(entity.get("power", default), default)
        if key == "health":
            base = _to_int(entity.get("health", 0), 0)
            return base if base > 0 else max(20, _get_stat(entity, "vitality", 10) * 10)
        return default

    if isinstance(entity, int):
        if key == "level":
            return 1
        if key == "health":
            return 100
        return default

    if key == "vitality":
        return _to_int(getattr(entity, "endurance", default), default)
    if key == "agility":
        return _to_int(getattr(entity, "agility", getattr(entity, "speed", default)), default)
    if key == "strength":
        return _to_int(getattr(entity, "strength", default), default)
    if key == "health":
        base_health = _to_int(getattr(entity, "health", 0), 0)
        if base_health > 0:
            return base_health
        return max(20, _get_stat(entity, "vitality", 10) * 10)
    if key == "intelligence":
        return _to_int(getattr(entity, "intelligence", default), default)
    if key == "level":
        return max(1, _to_int(getattr(entity, "level", 1), 1))
    return _to_int(getattr(entity, key, default), default)


def _extract_perks(entity: Any) -> List[HeroPerk]:
    if isinstance(entity, dict):
        return []
    perks = getattr(entity, "perks", [])
    return list(perks) if perks else []


def _extract_equipment(entity: Any) -> List[Any]:
    if isinstance(entity, dict):
        return []
    equipment = getattr(entity, "equipment_items", [])
    return list(equipment) if equipment else []


def _perk_bonus(entity: Any, kind: str) -> float:
    bonus: float = 0.0
    for hp in _extract_perks(entity):
        level = max(1, _to_int(getattr(hp, "perk_level", 1), 1))
        perk = getattr(hp, "perk", None)
        modifiers = getattr(perk, "modifiers", None) if perk is not None else None
        if isinstance(modifiers, dict):
            if kind == "attack":
                bonus += _to_float(modifiers.get("strength", 0)) * level
                bonus += _to_float(modifiers.get("damage", 0)) * level
            if kind == "defense":
                bonus += _to_float(modifiers.get("defense", 0)) * level
                bonus += _to_float(modifiers.get("endurance", 0)) * level
            if kind == "agility":
                bonus += _to_float(modifiers.get("agility", 0)) * level
            if kind == "dodge":
                bonus += _to_float(modifiers.get("dodge", 0)) * level
            continue

        perk_name = str(getattr(hp, "perk_name", "") or getattr(perk, "name", "")).lower()
        if not perk_name:
            continue
        if kind == "attack" and ("gunner" in perk_name or "berserk" in perk_name or "slayer" in perk_name):
            bonus += 2.0 * level
        elif kind == "defense" and ("defender" in perk_name or "guardian" in perk_name or "shield" in perk_name):
            bonus += 2.0 * level
        elif kind == "agility" and ("trickster" in perk_name or "assassin" in perk_name or "swift" in perk_name):
            bonus += 1.5 * level
        elif kind == "dodge" and ("trickster" in perk_name or "evasion" in perk_name):
            bonus += 1.0 * level
    return bonus


def _equipment_bonus(entity: Any, kind: str) -> float:
    bonus: float = 0.0
    for eq in _extract_equipment(entity):
        item = getattr(eq, "item", None)
        if item is None:
            continue
        slot = str(getattr(eq, "slot", "") or "").lower()
        if kind == "attack":
            attack = _to_float(getattr(item, "bonus_strength", 0))
            attack += _to_float(getattr(item, "bonus_intelligence", 0)) * 0.5
            if slot == "weapon":
                attack *= 1.35
            bonus += attack
        elif kind == "defense":
            def_bonus = _to_float(getattr(item, "bonus_defense", 0))
            def_bonus += _to_float(getattr(item, "bonus_health", 0)) * 0.1
            if slot in {"armor", "spacesuit", "shield", "helmet", "boots"}:
                def_bonus *= 1.15
            bonus += def_bonus
        elif kind == "agility":
            bonus += _to_float(getattr(item, "bonus_agility", 0))
    return bonus


def _derive_combat_stats(entity: Any) -> Dict[str, float]:
    strength = _to_float(_get_stat(entity, "strength", 10))
    agility = _to_float(_get_stat(entity, "agility", 10))
    intelligence = _to_float(_get_stat(entity, "intelligence", 8))
    vitality = _to_float(_get_stat(entity, "vitality", 10))
    level = _to_float(max(1, _get_stat(entity, "level", 1)))

    weapon_mod = _equipment_bonus(entity, "attack")
    armor_mod = _equipment_bonus(entity, "defense")
    agility_mod = _equipment_bonus(entity, "agility")

    attack_perk = _perk_bonus(entity, "attack")
    defense_perk = _perk_bonus(entity, "defense")
    agility_perk = _perk_bonus(entity, "agility")
    dodge_perk = _perk_bonus(entity, "dodge")

    attack_power = strength * 1.4 + intelligence * 0.6 + level * 1.1 + weapon_mod + attack_perk
    defense_power = vitality * 1.2 + armor_mod + defense_perk
    effective_agility = agility + agility_mod + agility_perk

    max_hp = max(50, int(_get_stat(entity, "health", int(vitality * 10 + level * 12))))
    return {
        "strength": strength,
        "agility": effective_agility,
        "intelligence": intelligence,
        "vitality": vitality,
        "level": level,
        "attack_power": attack_power,
        "defense_power": defense_power,
        "dodge_bonus": dodge_perk,
        "max_hp": float(max_hp),
    }


def _make_seed(*parts: Any) -> int:
    raw = "|".join(str(p) for p in parts)
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()
    return int(digest[:16], 16)


def _turn_order_key(state: FighterState, rng: random.Random) -> float:
    return state.stats["agility"] + state.stats["level"] * 0.2 + rng.random() * 0.001


def _dodge_chance(defender: FighterState) -> float:
    base = 0.02 + defender.stats["agility"] * 0.0025 + defender.stats["dodge_bonus"] * 0.002
    return max(0.02, min(0.45, base))


def _compute_damage(attacker: FighterState, defender: FighterState, rng: random.Random) -> Tuple[int, bool]:
    random_factor = rng.randint(-3, 6)
    if rng.random() < _dodge_chance(defender):
        return 0, True
    raw_damage = attacker.stats["attack_power"] - defender.stats["defense_power"] + random_factor
    damage = max(1, int(round(raw_damage)))
    return damage, False


def _select_target(opponents: List[FighterState], rng: random.Random) -> Optional[FighterState]:
    living = [op for op in opponents if op.alive]
    if not living:
        return None
    living.sort(key=lambda op: (op.current_hp, op.entity_id))
    lowest_hp = living[0].current_hp
    candidates = [op for op in living if op.current_hp == lowest_hp]
    if len(candidates) == 1:
        return candidates[0]
    return candidates[rng.randint(0, len(candidates) - 1)]


def _ensure_runtime_hp(entity: Any, stats: Dict[str, float]) -> int:
    if isinstance(entity, dict):
        hp = _to_int(entity.get("current_hp", 0), 0)
        if hp <= 0:
            hp = int(stats["max_hp"])
        entity["current_hp"] = hp
        return hp
    if isinstance(entity, int):
        return int(stats["max_hp"])

    hp = _to_int(getattr(entity, "_combat_hp", 0), 0)
    if hp <= 0:
        hp = int(stats["max_hp"])
    setattr(entity, "_combat_hp", hp)
    return hp


def _set_runtime_hp(entity: Any, hp: int) -> None:
    if isinstance(entity, dict):
        entity["current_hp"] = hp
        return
    if isinstance(entity, int):
        return
    setattr(entity, "_combat_hp", hp)


def _owner_id(entity: Any) -> Optional[int]:
    if isinstance(entity, dict):
        value = entity.get("owner_id", entity.get("user_id", None))
        return _to_int(value) if value is not None else None
    if isinstance(entity, int):
        return None
    if hasattr(entity, "owner_id"):
        return _to_int(getattr(entity, "owner_id"), 0)
    return None


async def resolve_action(
    db: AsyncSession,
    actor: Any,
    targets: List[Any],
    context: Any
) -> Dict[str, Any]:
    """
    Deterministic single-action resolver used by PvE/Raid turns.

    Damage formula:
        damage = attack_power - defense + random_factor

    Where attack/defense include base attributes, equipment modifiers and perk bonuses.
    Agility influences dodge chance and target tiebreaking.
    """
    if not targets:
        return {
            "actor_id": _entity_id(actor, 0),
            "action": "attack",
            "target_ids": [],
            "value": 0,
            "context": context,
            "timestamp": datetime.utcnow().isoformat() + "Z",
        }

    actor_id = _entity_id(actor, 0)
    valid_targets = [t for t in targets if _entity_id(t, 0) > 0]
    if not valid_targets:
        return {
            "actor_id": actor_id,
            "action": "attack",
            "target_ids": [],
            "value": 0,
            "context": context,
            "timestamp": datetime.utcnow().isoformat() + "Z",
        }

    actor_stats = _derive_combat_stats(actor)
    actor_state = FighterState(
        entity=actor,
        owner_id=_owner_id(actor),
        entity_id=actor_id,
        team="actor",
        max_hp=int(actor_stats["max_hp"]),
        current_hp=_ensure_runtime_hp(actor, actor_stats),
        stats=actor_stats,
    )

    target_states: List[FighterState] = []
    for t in valid_targets:
        ts = _derive_combat_stats(t)
        target_states.append(FighterState(
            entity=t,
            owner_id=_owner_id(t),
            entity_id=_entity_id(t),
            team="target",
            max_hp=int(ts["max_hp"]),
            current_hp=_ensure_runtime_hp(t, ts),
            stats=ts,
        ))

    seed = _make_seed(actor_state.entity_id, context, *(s.entity_id for s in target_states), actor_state.current_hp)
    rng = random.Random(seed)
    target = _select_target(target_states, rng)
    if target is None:
        return {
            "actor_id": actor_state.entity_id,
            "action": "attack",
            "target_ids": [],
            "value": 0,
            "context": context,
            "timestamp": datetime.utcnow().isoformat() + "Z",
        }

    damage, dodged = _compute_damage(actor_state, target, rng)
    new_hp = max(0, target.current_hp - damage)
    target.current_hp = new_hp
    _set_runtime_hp(target.entity, new_hp)

    return {
        "actor_id": actor_state.entity_id,
        "action": "attack" if not dodged else "miss",
        "target_ids": [target.entity_id],
        "value": int(damage),
        "target_hp": int(new_hp),
        "dodged": dodged,
        "context": context,
        "timestamp": datetime.utcnow().isoformat() + "Z",
    }


async def _load_player_team(db: AsyncSession, player_id: int, team_label: str) -> List[FighterState]:
    query = (
        select(Hero)
        .where(Hero.owner_id == player_id)
        .where(Hero.is_deleted == False)
        .options(
            selectinload(Hero.perks).selectinload(HeroPerk.perk),
            selectinload(Hero.equipment_items).selectinload(Equipment.item),
        )
        .order_by(Hero.level.desc(), Hero.id.asc())
        .limit(TEAM_SIZE)
    )
    result = await db.execute(query)
    heroes: List[Hero] = list(result.scalars().unique().all())

    team: List[FighterState] = []
    for hero in heroes:
        stats = _derive_combat_stats(hero)
        team.append(FighterState(
            entity=hero,
            owner_id=player_id,
            entity_id=hero.id,
            team=team_label,
            max_hp=int(stats["max_hp"]),
            current_hp=_ensure_runtime_hp(hero, stats),
            stats=stats,
        ))
    return team


def _team_alive(team: List[FighterState]) -> bool:
    return any(member.alive for member in team)


async def simulate_pvp_battle(
    db: AsyncSession,
    player1_id: int,
    player2_id: int
) -> Tuple[List[Dict[str, Any]], Optional[int]]:
    """
    Deterministic turn-based PvP simulation.

    Returns:
        (events, winner_user_id) where winner is None on draw.
    """
    events: List[Dict[str, Any]] = []

    team_a = await _load_player_team(db, player1_id, "A")
    team_b = await _load_player_team(db, player2_id, "B")

    if not team_a and not team_b:
        return events, None
    if not team_a:
        return events, player2_id
    if not team_b:
        return events, player1_id

    seed = _make_seed(
        "pvp",
        player1_id,
        player2_id,
        *(h.entity_id for h in team_a),
        *(h.entity_id for h in team_b),
    )
    rng = random.Random(seed)

    for round_no in range(1, MAX_ROUNDS + 1):
        if not _team_alive(team_a) or not _team_alive(team_b):
            break

        turn_order = [m for m in (team_a + team_b) if m.alive]
        turn_order.sort(key=lambda m: (_turn_order_key(m, rng), m.entity_id), reverse=True)

        for actor in turn_order:
            if not actor.alive:
                continue
            opponents = team_b if actor.team == "A" else team_a
            target = _select_target(opponents, rng)
            if target is None:
                continue

            damage, dodged = _compute_damage(actor, target, rng)
            target.current_hp = max(0, target.current_hp - damage)
            _set_runtime_hp(target.entity, target.current_hp)

            events.append({
                "actor_id": actor.entity_id,
                "action": "attack" if not dodged else "miss",
                "target_ids": [target.entity_id],
                "value": int(damage),
                "context": {
                    "round": round_no,
                    "attacker_team": actor.team,
                    "defender_team": target.team,
                },
                "target_hp": int(target.current_hp),
                "dodged": dodged,
                "timestamp": datetime.utcnow().isoformat() + "Z",
            })

            if not _team_alive(team_a) or not _team_alive(team_b):
                break

    alive_a = _team_alive(team_a)
    alive_b = _team_alive(team_b)
    if alive_a and not alive_b:
        winner_id: Optional[int] = player1_id
    elif alive_b and not alive_a:
        winner_id = player2_id
    else:
        winner_id = None

    return events, winner_id