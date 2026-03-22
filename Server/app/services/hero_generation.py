"""
Hero generation engine — v2

Produces a fully-formed hero by running 10 sequential generation layers.
Each layer has an independent success probability (from generation_config).
Successful layers improve stats, grant/upgrade skills, add tags, and
refine hidden coefficients.

The algorithm is *deterministic* given a seed — replaying the same seed
will reproduce the exact same hero.

Public API
──────────
    generate_hero(session, owner_id, *, locale, seed) -> Hero

Dependencies
────────────
    app.core.generation_config   – all tuneable constants
    app.core.hero_config         – body parts, locale map
    app.database.models.hero     – ORM models
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import random
from typing import Sequence

from faker import Faker
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.future import select

from app.core.generation_config import (
    COEFFICIENT_LAYER_BUMP,
    COEFFICIENT_RANGES,
    CORE_STATS,
    BASE_STAT_RANGE,
    GENERATION_VERSION,
    HIDDEN_TRAIT_LAYER_BUMP,
    HIDDEN_TRAIT_POOLS,
    HIDDEN_TRAIT_RANGE,
    INITIAL_HIDDEN_TRAIT_COUNT,
    INITIAL_SKILL_COUNT,
    INITIAL_TAG_COUNT,
    LAYER_COST_IMPROVEMENT_CHANCE,
    LAYER_FAMILY_UNLOCK,
    LAYER_NEW_HIDDEN_TRAIT_CHANCE,
    LAYER_NEW_SKILL_CHANCE,
    LAYER_NEW_TAG_CHANCE,
    LAYER_SKILL_UPGRADE_CHANCE,
    LAYER_STAT_BONUS_PCT,
    LAYER_SUCCESS_RATES,
    MAX_HIDDEN_TRAITS,
    MAX_SKILLS,
    MAX_TAGS,
    ROLE_COEFF_SCORING,
    ROLE_SKILL_SCORING,
    ROLE_STAT_SCORING,
    SECONDARY_ROLE_MIN_RATIO,
    SIGNATURE_SKILL_LAYER_THRESHOLD,
    SKILL_COST_SCALE,
    SKILL_POWER_SCALE,
    TAG_GROUP_WEIGHTS,
    TAG_POOLS,
)
from app.core.hero_config import BODY_PARTS, LOCALE_MAP
from app.database.models.hero import (
    Hero,
    HeroBodyPart,
    HeroCombatStats,
    HeroGenerationLayer,
    HeroHiddenTrait,
    HeroHistory,
    HeroSkill,
    HeroStats,
    HeroTag,
    SkillsCatalog,
)

logger = logging.getLogger("hero_gen")


# ═══════════════════════════════════════════════════════════════════
# Helpers
# ═══════════════════════════════════════════════════════════════════

def _make_seed() -> str:
    """Generate a 64-char hex seed from OS entropy."""
    return os.urandom(32).hex()


def _seed_rng(seed: str, layer: int) -> random.Random:
    """Return a deterministic Random instance for a given seed + layer.

    Using a per-layer sub-seed ensures that adding new logic in one
    layer doesn't shift the RNG sequence of later layers.
    """
    combined = f"{seed}:layer:{layer}"
    digest = hashlib.sha256(combined.encode()).digest()
    rng = random.Random()
    rng.seed(int.from_bytes(digest[:16], "big"))
    return rng


def _clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


# ═══════════════════════════════════════════════════════════════════
# 1. Stat rolling
# ═══════════════════════════════════════════════════════════════════

def _roll_base_stats(rng: random.Random) -> dict[str, int]:
    """Roll initial core stats from BASE_STAT_RANGE."""
    return {
        stat: rng.randint(*BASE_STAT_RANGE[stat])
        for stat in CORE_STATS
    }


def _apply_layer_stat_bonus(
    rng: random.Random,
    current_stats: dict[str, int],
    layer: int,
) -> dict[str, int]:
    """Add a percentage-based stat bonus for a successful layer."""
    updated = dict(current_stats)
    for stat in CORE_STATS:
        lo_pct, hi_pct = LAYER_STAT_BONUS_PCT[stat]
        # Higher layers give slightly bigger bonuses.
        scale = 1.0 + (layer - 1) * 0.08
        bonus_pct = rng.uniform(lo_pct, hi_pct) * scale
        bonus = max(1, int(current_stats[stat] * bonus_pct))
        updated[stat] = current_stats[stat] + bonus
    return updated


# ═══════════════════════════════════════════════════════════════════
# 2. Coefficient rolling
# ═══════════════════════════════════════════════════════════════════

def _roll_coefficients(rng: random.Random) -> dict[str, float]:
    """Roll initial hidden coefficients."""
    return {
        name: round(rng.uniform(*rng_range), 4)
        for name, rng_range in COEFFICIENT_RANGES.items()
    }


def _bump_coefficients(
    rng: random.Random,
    current: dict[str, float],
) -> dict[str, float]:
    """Nudge coefficients on a successful layer."""
    updated = dict(current)
    for name, bump in COEFFICIENT_LAYER_BUMP.items():
        delta = rng.uniform(-bump, bump)
        lo, hi = COEFFICIENT_RANGES[name]
        updated[name] = round(_clamp(current[name] + delta, lo, hi), 4)
    return updated


# ═══════════════════════════════════════════════════════════════════
# 3. Tag generation
# ═══════════════════════════════════════════════════════════════════

def _pick_tags(
    rng: random.Random,
    count: int,
    existing_codes: set[str],
) -> list[tuple[str, str, float | None]]:
    """Return up to *count* new (tag_code, tag_group, tag_value) tuples."""
    result: list[tuple[str, str, float | None]] = []
    groups = list(TAG_POOLS.keys())
    weights = [TAG_GROUP_WEIGHTS.get(g, 1.0) for g in groups]

    for _ in range(count * 3):  # over-sample to account for dupes
        if len(result) >= count:
            break
        group = rng.choices(groups, weights=weights, k=1)[0]
        pool = TAG_POOLS[group]
        code = rng.choice(pool)
        if code in existing_codes:
            continue
        existing_codes.add(code)
        value = round(rng.uniform(0.5, 1.5), 2) if rng.random() < 0.4 else None
        result.append((code, group, value))
    return result


# ═══════════════════════════════════════════════════════════════════
# 4. Hidden traits
# ═══════════════════════════════════════════════════════════════════

def _pick_hidden_traits(
    rng: random.Random,
    count: int,
    existing_codes: set[str],
) -> list[tuple[str, float]]:
    """Return up to *count* new (trait_code, trait_value) tuples."""
    available = [t for t in HIDDEN_TRAIT_POOLS if t not in existing_codes]
    if not available:
        return []
    chosen = rng.sample(available, min(count, len(available)))
    lo, hi = HIDDEN_TRAIT_RANGE
    return [(code, round(rng.uniform(lo, hi), 4)) for code in chosen]


def _bump_hidden_traits(
    rng: random.Random,
    traits: dict[str, float],
) -> dict[str, float]:
    """Nudge existing hidden trait values on a successful layer."""
    updated = dict(traits)
    lo_bump, hi_bump = HIDDEN_TRAIT_LAYER_BUMP
    lo_val, hi_val = HIDDEN_TRAIT_RANGE
    for code in list(updated):
        delta = rng.uniform(lo_bump, hi_bump)
        updated[code] = round(_clamp(updated[code] + delta, lo_val, hi_val), 4)
    return updated


# ═══════════════════════════════════════════════════════════════════
# 5. Skill generation
# ═══════════════════════════════════════════════════════════════════

async def _fetch_catalog_skills(
    session: AsyncSession,
    families: list[str],
    exclude_codes: set[str],
) -> list[SkillsCatalog]:
    """Query the skills_catalog for skills matching the given families."""
    stmt = (
        select(SkillsCatalog)
        .where(SkillsCatalog.skill_family.in_(families))
    )
    if exclude_codes:
        stmt = stmt.where(~SkillsCatalog.skill_code.in_(exclude_codes))
    result = await session.execute(stmt)
    return list(result.scalars().all())


def _create_hero_skill(
    catalog_entry: SkillsCatalog,
    gen_level: int,
    cost_gen_level: int,
    slot_index: int,
    is_signature: bool = False,
) -> dict:
    """Build kwargs dict for a HeroSkill from a catalog entry."""
    power_scale = SKILL_POWER_SCALE.get(gen_level, 1.0)
    cost_scale = SKILL_COST_SCALE.get(cost_gen_level, 1.0)

    return dict(
        skill_code=catalog_entry.skill_code,
        generation_level=gen_level,
        cost_generation_level=cost_gen_level,
        power_value=int(catalog_entry.power_base * power_scale),
        duration_value=round(catalog_entry.duration_base * (1 + (gen_level - 1) * 0.10), 2),
        cooldown_value=round(max(0.5, catalog_entry.cooldown_base * (1 - (gen_level - 1) * 0.03)), 2),
        stamina_cost_value=max(1, int(catalog_entry.stamina_cost_base * cost_scale)),
        radius_value=round(catalog_entry.radius_base * (1 + (gen_level - 1) * 0.05), 2),
        upgrade_count=0,
        source_type="GENERATION",
        slot_index=slot_index,
        is_signature=is_signature,
        payload_json=json.dumps({"catalog_id": catalog_entry.id}),
    )


def _upgrade_skill_dict(skill_kwargs: dict, new_gen_level: int) -> dict:
    """In-place upgrade an existing skill dict to a higher gen level."""
    skill_kwargs["upgrade_count"] = skill_kwargs.get("upgrade_count", 0) + 1
    old_scale = SKILL_POWER_SCALE.get(skill_kwargs["generation_level"], 1.0)
    new_scale = SKILL_POWER_SCALE.get(new_gen_level, 1.0)
    if old_scale > 0:
        ratio = new_scale / old_scale
        skill_kwargs["power_value"] = int(skill_kwargs["power_value"] * ratio)
        skill_kwargs["duration_value"] = round(skill_kwargs["duration_value"] * 1.05, 2)
        skill_kwargs["cooldown_value"] = round(max(0.5, skill_kwargs["cooldown_value"] * 0.97), 2)
    skill_kwargs["generation_level"] = new_gen_level
    return skill_kwargs


def _improve_skill_cost(skill_kwargs: dict) -> dict:
    """Reduce stamina cost by bumping cost_generation_level."""
    cgl = skill_kwargs.get("cost_generation_level", 1)
    if cgl < 10:
        new_cgl = cgl + 1
        old_scale = SKILL_COST_SCALE.get(cgl, 1.0)
        new_scale = SKILL_COST_SCALE.get(new_cgl, 1.0)
        if old_scale > 0:
            original_base = skill_kwargs["stamina_cost_value"] / old_scale
            skill_kwargs["stamina_cost_value"] = max(1, int(original_base * new_scale))
        skill_kwargs["cost_generation_level"] = new_cgl
    return skill_kwargs


# ═══════════════════════════════════════════════════════════════════
# 6. Role assignment
# ═══════════════════════════════════════════════════════════════════

def _score_roles(
    stats: dict[str, int],
    skill_families: dict[str, int],
    coefficients: dict[str, float],
) -> dict[str, float]:
    """Compute a weighted score for every role."""
    scores: dict[str, float] = {}
    for role in ROLE_STAT_SCORING:
        s = 0.0
        for stat, weight in ROLE_STAT_SCORING[role].items():
            s += stats.get(stat, 0) * weight
        for family, weight in ROLE_SKILL_SCORING[role].items():
            s += skill_families.get(family, 0) * weight * 10
        for coeff, weight in ROLE_COEFF_SCORING.get(role, {}).items():
            s += coefficients.get(coeff, 0) * weight * 20
        scores[role] = round(s, 2)
    return scores


def _assign_roles(
    stats: dict[str, int],
    skill_families: dict[str, int],
    coefficients: dict[str, float],
) -> tuple[str, str | None]:
    """Return (primary_role, secondary_role)."""
    scores = _score_roles(stats, skill_families, coefficients)
    ranked = sorted(scores.items(), key=lambda x: -x[1])

    primary = ranked[0][0]
    secondary = None
    if len(ranked) > 1:
        runner_up_role, runner_up_score = ranked[1]
        if runner_up_score >= ranked[0][1] * SECONDARY_ROLE_MIN_RATIO:
            secondary = runner_up_role

    return primary, secondary


# ═══════════════════════════════════════════════════════════════════
# 7. Main generation function
# ═══════════════════════════════════════════════════════════════════

async def generate_hero(
    session: AsyncSession,
    owner_id: int,
    *,
    locale: str = "en",
    seed: str | None = None,
) -> Hero:
    """Generate a complete hero through all 10 generation layers.

    Returns the new Hero ORM instance (flushed, not committed).
    The caller is responsible for committing the session.

    Parameters
    ----------
    session : AsyncSession
        Active database session.
    owner_id : int
        User ID who will own this hero.
    locale : str
        Locale for name generation ('en', 'pl', 'uk').
    seed : str | None
        Hex seed for deterministic generation.  If None, one is created.
    """
    # ── Seed ──────────────────────────────────────────────────────
    if seed is None:
        seed = _make_seed()

    # ── Name (uses layer-0 sub-seed so it's stable) ──────────────
    rng0 = _seed_rng(seed, 0)
    fake = Faker(LOCALE_MAP.get(locale, "en_US"))
    fake.seed_instance(rng0.randint(0, 2**31))
    name = fake.name()

    # ── Layer 1: always succeeds — base stats, tags, traits ──────
    rng1 = _seed_rng(seed, 1)
    stats = _roll_base_stats(rng1)
    coefficients = _roll_coefficients(rng1)

    # Tags
    tag_codes: set[str] = set()
    tags: list[tuple[str, str, float | None]] = _pick_tags(rng1, INITIAL_TAG_COUNT, tag_codes)

    # Hidden traits
    trait_codes: set[str] = set()
    hidden_traits: dict[str, float] = {}
    for code, val in _pick_hidden_traits(rng1, INITIAL_HIDDEN_TRAIT_COUNT, trait_codes):
        trait_codes.add(code)
        hidden_traits[code] = val

    # Skills — fetch from catalog
    available_families_1 = LAYER_FAMILY_UNLOCK.get(1, ["COMBAT"])
    catalog_pool = await _fetch_catalog_skills(session, available_families_1, set())
    skill_dicts: list[dict] = []
    owned_skill_codes: set[str] = set()

    if catalog_pool:
        chosen = rng1.sample(catalog_pool, min(INITIAL_SKILL_COUNT, len(catalog_pool)))
        for idx, cat_entry in enumerate(chosen):
            skill_dicts.append(_create_hero_skill(cat_entry, gen_level=1, cost_gen_level=1, slot_index=idx))
            owned_skill_codes.add(cat_entry.skill_code)

    # Layer results tracking
    layer_results: list[dict] = []
    highest_success_layer = 1

    layer_results.append({
        "layer_index": 1,
        "success": True,
        "success_rate_used": LAYER_SUCCESS_RATES[1],
        "roll_value": 0.0,  # layer 1 auto-succeeds
        "payload_json": json.dumps({
            "stats_snapshot": dict(stats),
            "skills_granted": [s["skill_code"] for s in skill_dicts],
            "tags_granted": [t[0] for t in tags],
        }),
    })

    # ── Layers 2..10 ─────────────────────────────────────────────
    for layer in range(2, 11):
        rng_l = _seed_rng(seed, layer)
        success_rate = LAYER_SUCCESS_RATES.get(layer, 0.0)
        roll = rng_l.random()
        success = roll <= success_rate

        layer_log: dict = {
            "stats_delta": {},
            "skills_granted": [],
            "skills_upgraded": [],
            "cost_improvements": [],
            "tags_granted": [],
            "traits_granted": [],
        }

        if success:
            highest_success_layer = layer

            # ─ Stat improvement ──────────────────────────────────
            old_stats = dict(stats)
            stats = _apply_layer_stat_bonus(rng_l, stats, layer)
            layer_log["stats_delta"] = {
                s: stats[s] - old_stats[s] for s in CORE_STATS
            }

            # ─ Coefficient refinement ────────────────────────────
            coefficients = _bump_coefficients(rng_l, coefficients)

            # ─ Skill: new or upgrade ─────────────────────────────
            families = LAYER_FAMILY_UNLOCK.get(layer, ["COMBAT"])
            if len(skill_dicts) < MAX_SKILLS and rng_l.random() < LAYER_NEW_SKILL_CHANCE:
                new_pool = await _fetch_catalog_skills(session, families, owned_skill_codes)
                if new_pool:
                    cat = rng_l.choice(new_pool)
                    idx = len(skill_dicts)
                    skill_dicts.append(_create_hero_skill(cat, gen_level=layer, cost_gen_level=1, slot_index=idx))
                    owned_skill_codes.add(cat.skill_code)
                    layer_log["skills_granted"].append(cat.skill_code)
            elif skill_dicts and rng_l.random() < LAYER_SKILL_UPGRADE_CHANCE:
                target = rng_l.choice(skill_dicts)
                _upgrade_skill_dict(target, layer)
                layer_log["skills_upgraded"].append(target["skill_code"])

            # ─ Cost improvement ──────────────────────────────────
            if skill_dicts and rng_l.random() < LAYER_COST_IMPROVEMENT_CHANCE:
                target = rng_l.choice(skill_dicts)
                _improve_skill_cost(target)
                layer_log["cost_improvements"].append(target["skill_code"])

            # ─ Tags ──────────────────────────────────────────────
            if len(tags) < MAX_TAGS and rng_l.random() < LAYER_NEW_TAG_CHANCE:
                new_tags = _pick_tags(rng_l, 1, tag_codes)
                tags.extend(new_tags)
                layer_log["tags_granted"] = [t[0] for t in new_tags]

            # ─ Hidden traits ─────────────────────────────────────
            hidden_traits = _bump_hidden_traits(rng_l, hidden_traits)
            if len(hidden_traits) < MAX_HIDDEN_TRAITS and rng_l.random() < LAYER_NEW_HIDDEN_TRAIT_CHANCE:
                new_ht = _pick_hidden_traits(rng_l, 1, trait_codes)
                for code, val in new_ht:
                    trait_codes.add(code)
                    hidden_traits[code] = val
                    layer_log["traits_granted"].append(code)

        layer_results.append({
            "layer_index": layer,
            "success": success,
            "success_rate_used": success_rate,
            "roll_value": round(roll, 6),
            "payload_json": json.dumps(layer_log),
        })

    # ── Signature skill ──────────────────────────────────────────
    if highest_success_layer >= SIGNATURE_SKILL_LAYER_THRESHOLD and skill_dicts:
        best = max(skill_dicts, key=lambda s: s.get("power_value", 0))
        best["is_signature"] = True

    # ── Role assignment ──────────────────────────────────────────
    skill_family_counts: dict[str, int] = {}
    for sd in skill_dicts:
        code = sd["skill_code"]
        result = await session.execute(
            select(SkillsCatalog.skill_family).where(SkillsCatalog.skill_code == code)
        )
        row = result.first()
        if row:
            family = row[0] if isinstance(row[0], str) else row[0].value
            skill_family_counts[family] = skill_family_counts.get(family, 0) + 1

    primary_role, secondary_role = _assign_roles(stats, skill_family_counts, coefficients)

    # ── Persist: Hero ────────────────────────────────────────────
    hero = Hero(
        owner_id=owner_id,
        name=name,
        generation_seed=seed,
        generation_version=GENERATION_VERSION,
        hero_generation_level=highest_success_layer,
        primary_role=primary_role,
        secondary_role=secondary_role,
        hero_coherence=coefficients["hero_coherence"],
        stability=coefficients["stability"],
        control_susceptibility=coefficients["control_susceptibility"],
        transfer_conductivity=coefficients["transfer_conductivity"],
        execution_resonance=coefficients["execution_resonance"],
        affinity_bias=coefficients["affinity_bias"],
        current_hp=stats["health"],
        locale=locale,
    )
    session.add(hero)
    await session.flush()

    # ── Persist: Stats ───────────────────────────────────────────
    session.add(HeroStats(
        hero_id=hero.id,
        **{stat: stats[stat] for stat in CORE_STATS},
    ))

    # ── Persist: Generation layers ───────────────────────────────
    for lr in layer_results:
        session.add(HeroGenerationLayer(hero_id=hero.id, **lr))

    # ── Persist: Tags ────────────────────────────────────────────
    for code, group, value in tags:
        session.add(HeroTag(
            hero_id=hero.id,
            tag_code=code,
            tag_group=group,
            tag_value=value,
        ))

    # ── Persist: Skills ──────────────────────────────────────────
    for sd in skill_dicts:
        session.add(HeroSkill(hero_id=hero.id, **sd))

    # ── Persist: Hidden traits ───────────────────────────────────
    for code, val in hidden_traits.items():
        session.add(HeroHiddenTrait(
            hero_id=hero.id,
            trait_code=code,
            trait_value=val,
        ))

    # ── Persist: Body parts ──────────────────────────────────────
    for bp in BODY_PARTS:
        session.add(HeroBodyPart(
            hero_id=hero.id,
            part_name=bp["part_name"],
            max_hp=bp["max_hp"],
            current_hp=bp["max_hp"],
            armor=bp["armor"],
        ))

    # ── Persist: Combat stats (zeroed) ───────────────────────────
    session.add(HeroCombatStats(hero_id=hero.id))

    # ── Persist: History entry ───────────────────────────────────
    session.add(HeroHistory(
        hero_id=hero.id,
        event_type="created",
        event_data=json.dumps({
            "generation_version": GENERATION_VERSION,
            "seed": seed,
            "generation_level": highest_success_layer,
            "primary_role": primary_role,
            "secondary_role": secondary_role,
            "stats": stats,
            "coefficients": {k: round(v, 4) for k, v in coefficients.items()},
            "skill_codes": [sd["skill_code"] for sd in skill_dicts],
            "tag_codes": [t[0] for t in tags],
        }),
    ))

    await session.flush()
    logger.info(
        "Generated hero %s (id=%d) for owner %d — gen_level=%d, role=%s/%s, "
        "%d skills, %d tags, seed=%s",
        name, hero.id, owner_id, highest_success_layer,
        primary_role, secondary_role or "none",
        len(skill_dicts), len(tags), seed[:16] + "…",
    )

    return hero