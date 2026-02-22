import yaml
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.database.models.resource import GameResource, ResourceType
import asyncio

DATABASE_URL = "postgresql+asyncpg://user:password@localhost/dbname"  # Заміни на свій
YAML_PATH = "app/database/resources.yaml"

async def seed_resources():
    engine = create_async_engine(DATABASE_URL, echo=True)
    async_session = sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)
    async with async_session() as session:
        with open(YAML_PATH, encoding="utf-8") as f:
            data = yaml.safe_load(f)
        for res in data:
            obj = GameResource(
                id=res["id"],
                name=res["name"],
                type=ResourceType(res["type"]),
                source=res["source"],
                description=res.get("description", "")
            )
            session.add(obj)
        await session.commit()
    await engine.dispose()

if __name__ == "__main__":
    asyncio.run(seed_resources()) 