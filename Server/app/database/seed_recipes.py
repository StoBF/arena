import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.core.config import settings
from app.database.models.craft import CraftRecipe, CraftRecipeResource
from app.database.models.resource import GameResource

async def seed_recipes():
    # Use settings.DATABASE_URL
    engine = create_async_engine(settings.DATABASE_URL, echo=True)
    AsyncSessionLocal = sessionmaker(
        bind=engine, class_=AsyncSession, expire_on_commit=False
    )
    async with AsyncSessionLocal() as session:
        # Example recipe definitions
        recipes = [
            {
                "id": 1,
                "name": "Лазерний меч",
                "item_type": "weapon",
                "grade": 3,
                "result_item_id": None,
                "boss_id": None,
                "craft_time_sec": 300,
                "resources": [
                    {"resource_id": 1, "quantity": 5, "type": "pvp"},
                    {"resource_id": 3, "quantity": 1, "type": "pvp"},
                    {"resource_id":101, "quantity":2, "type":"pve"},
                ]
            },
            # Add more recipes as needed
        ]
        for r in recipes:
            recipe = CraftRecipe(
                id=r["id"],
                name=r["name"],
                item_type=r["item_type"],
                grade=r["grade"],
                result_item_id=r.get("result_item_id"),
                boss_id=r.get("boss_id"),
                craft_time_sec=r["craft_time_sec"]
            )
            session.add(recipe)
            await session.flush()
            # Add ingredients
            for comp in r["resources"]:
                link = CraftRecipeResource(
                    recipe_id=recipe.id,
                    resource_id=comp["resource_id"],
                    quantity=comp["quantity"],
                    type=comp["type"]
                )
                session.add(link)
        await session.commit()
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(seed_recipes()) 