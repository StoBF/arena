import random
import math
import logging
from faker import Faker
from fastapi import HTTPException
from app.core.hero_config import BASE_SUCCESS_RATES, MAX_BONUS_FACTOR, ATTRIBUTE_RANGES, PERKS_LIST, NICKNAME_MAP, LOCALE_MAP
from app.database.models.hero import Hero, HeroPerk
from app.database.models.perk import Perk
from sqlalchemy.future import select

logger = logging.getLogger("hero_gen")

def calc_currency_bonus(base, currency, k=0.001):
    # `currency` may be a Decimal in our code; math.exp only works with floats
    # so convert before doing the calculation.  Return a float since this is
    # used for probability checks.
    max_bonus = base * MAX_BONUS_FACTOR
    bonus = max_bonus * (1 - math.exp(-k * float(currency)))
    return bonus

def roll_attributes(gen):
    ranges = ATTRIBUTE_RANGES[gen]
    return {attr: random.randint(*rng) for attr, rng in ranges.items()}

async def roll_perks(session, gen):
    num_perks = gen
    level_min = (gen - 1) * 10 + 1
    level_max = gen * 10
    # Вибираємо випадкові перки з таблиці perks
    perks = (await session.execute(select(Perk))).scalars().all()
    chosen = random.sample(perks, min(num_perks, len(perks)))
    return [(p.id, random.randint(level_min, level_max)) for p in chosen]

def choose_dominant_trait(attrs, perks, perk_objs=None):
    max_attr = max(attrs.items(), key=lambda x: x[1])
    max_perk = max(perks, key=lambda x: x[1]) if perks else (None, 0)
    if max_perk[1] >= 100 or (max_perk[1] > max_attr[1] + 10):
        if perk_objs:
            return next((p.name for p in perk_objs if p.id == max_perk[0]), max_attr[0])
        return str(max_perk[0])
    return max_attr[0]

async def generate_hero(session, owner_id, target_gen, currency, locale="en", max_tries=5, seed=None):
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
                raise HTTPException(429, "Забагато невдалих спроб")
            continue
        fake = Faker(LOCALE_MAP.get(locale, "en_US"))
        name = fake.name()
        attrs = roll_attributes(target_gen)
        perks = await roll_perks(session, target_gen)
        perk_objs = (await session.execute(select(Perk).where(Perk.id.in_([p[0] for p in perks])))).scalars().all()
        trait_key = choose_dominant_trait(attrs, perks, perk_objs)
        nickname = NICKNAME_MAP.get(locale, NICKNAME_MAP["en"]).get(trait_key, "the Hero")
        new_hero = Hero(
            name=name,
            generation=target_gen,
            nickname=nickname,
            locale=locale,
            owner_id=owner_id,
            strength=attrs["strength"],
            agility=attrs["agility"],
            intelligence=attrs["intelligence"],
            endurance=attrs["endurance"],
            speed=attrs["speed"],
            health=attrs["health"],
            defense=attrs["defense"],
            luck=attrs["luck"],
            field_of_view=attrs["field_of_view"]
        )
        session.add(new_hero)
        await session.flush()
        for perk_id, perk_level in perks:
            session.add(HeroPerk(hero_id=new_hero.id, perk_id=perk_id, perk_level=perk_level))
        await session.commit()
        await session.refresh(new_hero)
        return new_hero