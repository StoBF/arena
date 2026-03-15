import random
import math
import logging
import json
from faker import Faker
from fastapi import HTTPException
from app.core.hero_config import (
    BASE_SUCCESS_RATES, MAX_BONUS_FACTOR, ATTRIBUTE_RANGES, PERKS_LIST,
    NICKNAME_MAP, LOCALE_MAP, ARCHETYPE_STAT_WEIGHTS, ARCHETYPE_STARTER_ABILITIES,
    PRIMARY_STATS, BODY_PARTS,
)
from app.database.models.hero import Hero, HeroPerk, HeroAbility, HeroHistory, HeroBodyPart, HeroCombatStats, HeroArchetype
from app.database.models.perk import Perk
from app.core.derived_stats import compute_derived_for_hero
from sqlalchemy.future import select

logger = logging.getLogger("hero_gen")


# ---------------------------------------------------------------------------
# Probability helpers
# ---------------------------------------------------------------------------

def calc_currency_bonus(base, currency, k=0.001):
    # `currency` may be a Decimal in our code; math.exp only works with floats
    # so convert before doing the calculation.  Return a float since this is
    # used for probability checks.
    max_bonus = base * MAX_BONUS_FACTOR
    bonus = max_bonus * (1 - math.exp(-k * float(currency)))
    return bonus


# ---------------------------------------------------------------------------
# Attribute rolling
# ---------------------------------------------------------------------------

def roll_attributes(gen: int, archetype: str | None = None) -> dict[str, int]:
    """Roll primary stats for a generation, optionally weighted by archetype."""
    ranges = ATTRIBUTE_RANGES[gen]
    attrs = {attr: random.randint(*rng) for attr, rng in ranges.items()}

    # Apply archetype stat weights (multiply raw roll, then round)
    if archetype and archetype in ARCHETYPE_STAT_WEIGHTS:
        weights = ARCHETYPE_STAT_WEIGHTS[archetype]
        for stat in PRIMARY_STATS:
            if stat in attrs and stat in weights:
                attrs[stat] = max(1, round(attrs[stat] * weights[stat]))

    return attrs


# ---------------------------------------------------------------------------
# Archetype selection
# ---------------------------------------------------------------------------

def pick_archetype(preferred: str | None = None) -> str:
    """Return a valid archetype string.  If preferred is given and valid, use it;
    otherwise pick a weighted random one (CHIMERA is rarer)."""
    valid = [e.value for e in HeroArchetype]
    if preferred and preferred.upper() in valid:
        return preferred.upper()
    # Weighted: CHIMERA is rarer
    weights = [10, 10, 10, 10, 10, 10, 5]  # same order as enum
    return random.choices(valid, weights=weights, k=1)[0]


# ---------------------------------------------------------------------------
# Perk rolling (unchanged logic)
# ---------------------------------------------------------------------------

async def roll_perks(session, gen):
    num_perks = gen
    level_min = (gen - 1) * 10 + 1
    level_max = gen * 10
    perks = (await session.execute(select(Perk))).scalars().all()
    chosen = random.sample(perks, min(num_perks, len(perks)))
    return [(p.id, random.randint(level_min, level_max)) for p in chosen]


# ---------------------------------------------------------------------------
# Nickname
# ---------------------------------------------------------------------------

def choose_dominant_trait(attrs, perks, perk_objs=None):
    max_attr = max(attrs.items(), key=lambda x: x[1])
    max_perk = max(perks, key=lambda x: x[1]) if perks else (None, 0)
    if max_perk[1] >= 100 or (max_perk[1] > max_attr[1] + 10):
        if perk_objs:
            return next((p.name for p in perk_objs if p.id == max_perk[0]), max_attr[0])
        return str(max_perk[0])
    return max_attr[0]


# ---------------------------------------------------------------------------
# Main generation function
# ---------------------------------------------------------------------------

async def generate_hero(session, owner_id, target_gen, currency, locale="en", max_tries=5, seed=None, preferred_archetype=None):
    """Generate a new hero with the S.P.E.I.A.L.W stat model, archetype,
    starter ability, and initial derived-stat based HP."""
    if target_gen < 1 or target_gen > 10:
        raise HTTPException(400, "Invalid generation level")
    if seed is not None:
        random.seed(seed)

    attempt = 0
    while attempt < max_tries:
        base = BASE_SUCCESS_RATES[target_gen]
        chance = base + calc_currency_bonus(base, currency)
        chance = min(chance, base * 1.5)
        if random.random() > chance:
            attempt += 1
            logger.warning(f"Hero generation failed (attempt {attempt}/{max_tries}) for owner {owner_id}, gen {target_gen}, currency {currency}")
            if attempt >= max_tries:
                raise HTTPException(429, "Too many failed attempts")
            continue

        # --- Name ---
        fake = Faker(LOCALE_MAP.get(locale, "en_US"))
        name = fake.name()

        # --- Archetype ---
        archetype = pick_archetype(preferred_archetype)

        # --- Primary stats ---
        attrs = roll_attributes(target_gen, archetype)

        # --- Perks ---
        perks = await roll_perks(session, target_gen)
        perk_objs = (await session.execute(select(Perk).where(Perk.id.in_([p[0] for p in perks])))).scalars().all()

        # --- Nickname ---
        trait_key = choose_dominant_trait(attrs, perks, perk_objs)
        nickname = NICKNAME_MAP.get(locale, NICKNAME_MAP["en"]).get(trait_key, "the Hero")

        # --- Create hero ---
        new_hero = Hero(
            name=name,
            generation=target_gen,
            nickname=nickname,
            locale=locale,
            owner_id=owner_id,
            archetype=archetype,
            strength=attrs["strength"],
            perception=attrs["perception"],
            endurance=attrs["endurance"],
            intelligence=attrs["intelligence"],
            agility=attrs["agility"],
            luck=attrs["luck"],
            willpower=attrs["willpower"],
        )
        session.add(new_hero)
        await session.flush()

        # Set initial HP from derived stats
        derived = compute_derived_for_hero(new_hero)
        new_hero.current_hp = derived.max_hp

        # --- Perks ---
        for perk_id, perk_level in perks:
            session.add(HeroPerk(hero_id=new_hero.id, perk_id=perk_id, perk_level=perk_level))

        # --- Starter ability from archetype ---
        starter = ARCHETYPE_STARTER_ABILITIES.get(archetype)
        if starter:
            session.add(HeroAbility(
                hero_id=new_hero.id,
                ability_code=starter["ability_code"],
                ability_name=starter["ability_name"],
                ability_type=starter["ability_type"],
                ability_domain=starter["ability_domain"],
                ability_level=1,
                source="generation",
                metadata_json=json.dumps({"granted_at_gen": target_gen}),
            ))

        # --- History entry ---
        session.add(HeroHistory(
            hero_id=new_hero.id,
            event_type="created",
            event_data=json.dumps({
                "generation": target_gen,
                "archetype": archetype,
                "attrs": attrs,
                "currency_spent": float(currency),
            }),
        ))

        # --- Body parts ---
        for bp in BODY_PARTS:
            session.add(HeroBodyPart(
                hero_id=new_hero.id,
                part_name=bp["part_name"],
                max_hp=bp["max_hp"],
                current_hp=bp["max_hp"],
                armor=bp["armor"],
            ))

        # --- Combat stats (zeroed) ---
        session.add(HeroCombatStats(hero_id=new_hero.id))

        await session.flush()
        return new_hero