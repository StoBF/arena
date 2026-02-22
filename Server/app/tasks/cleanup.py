import asyncio
import logging
from datetime import datetime, timedelta
from sqlalchemy.future import select
from app.database.models.hero import Hero
from app.database.session import AsyncSessionLocal

async def delete_old_heroes_task():
    while True:
        await asyncio.sleep(3600)  # раз на годину
        async with AsyncSessionLocal() as session:
            async with session.begin():
                cutoff = datetime.utcnow() - timedelta(days=7)
                result = await session.execute(
                    select(Hero).where(Hero.is_deleted == True, Hero.deleted_at < cutoff)
                )
                old_heroes = result.scalars().all()
                if old_heroes:
                    logging.info(f"[CLEANUP] Видаляю {len(old_heroes)} героїв, що були видалені понад 7 днів тому.")
                for hero in old_heroes:
                    logging.info(f"[CLEANUP] Видалено героя id={hero.id}, name={hero.name}")
                    await session.delete(hero)
                if not old_heroes:
                    logging.info("[CLEANUP] Немає героїв для видалення.") 

async def revive_dead_heroes_task():
    while True:
        await asyncio.sleep(60)  # раз на хвилину
        async with AsyncSessionLocal() as session:
            async with session.begin():
                now = datetime.utcnow()
                result = await session.execute(
                    select(Hero).where(Hero.is_dead == True, Hero.dead_until != None, Hero.dead_until <= now)
                )
                to_revive = result.scalars().all()
                for hero in to_revive:
                    hero.is_dead = False
                    hero.dead_until = None
                    logging.info(f"[REVIVE] Герой id={hero.id}, name={hero.name} відновлений!")
            if not to_revive:
                logging.info("[REVIVE] Немає героїв для відродження.") 