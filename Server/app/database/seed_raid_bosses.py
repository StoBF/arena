import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.database.models.raid_boss import RaidBoss, RaidDropItem, RecipeDrop

DATABASE_URL = "postgresql+asyncpg://user:password@localhost/dbname"  # Заміни на свій

async def seed_raid_bosses():
    engine = create_async_engine(DATABASE_URL, echo=True)
    async_session = sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with async_session() as session:
        # Приклад босів
        boss1 = RaidBoss(id=1, name="Плазмоїд", gen_min=1, gen_max=3)
        boss2 = RaidBoss(id=2, name="Кібердракон", gen_min=2, gen_max=5)
        boss3 = RaidBoss(id=3, name="Хаос-Лорд", gen_min=4, gen_max=7)
        session.add_all([boss1, boss2, boss3])
        await session.flush()
        # Дропи
        session.add_all([
            RaidDropItem(boss_id=1, item_name="Плазмова батарея", chance=0.25),
            RaidDropItem(boss_id=2, item_name="Кіберсердце", chance=0.20),
            RaidDropItem(boss_id=3, item_name="Кристал хаосу", chance=0.18),
        ])
        # Дропи рецептів (приклад)
        session.add_all([
            RecipeDrop(boss_id=1, recipe_id=1, chance=0.03),
            RecipeDrop(boss_id=2, recipe_id=2, chance=0.02),
            RecipeDrop(boss_id=3, recipe_id=3, chance=0.01),
        ])
        await session.commit()
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(seed_raid_bosses()) 