from dotenv import load_dotenv
load_dotenv()  # тепер os.getenv() підхоплює ваш .env

import logging
import urllib.parse
import asyncpg
import asyncio
from app.core.log_config import setup_logging

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException
from sqlalchemy.exc import SQLAlchemyError
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from sqlalchemy import text
from app.core.redis_cache import redis_cache

from app.core.config import settings
from app.database.session import create_db_and_tables, AsyncSessionLocal, engine
from app.routers import auth, hero, auction, bid, announcement, inventory, equipment, workshop
from app.tasks.cleanup import delete_old_heroes_task
from app.tasks.auctions import close_expired_auctions_task
from app.services.auction import AuctionService
from app.routers.health import router as health_router
from app.routers.raid import router as raid_router
from app.routers.craft import router as craft_router
from app.routers.pvp import router as pvp_router
from app.routers.tournaments import router as tournaments_router
from app.routers.events import router as events_router

setup_logging()

tags_metadata = [
    {"name": "Auth", "description": "Authentication and user management."},
    {"name": "Heroes", "description": "Hero CRUD and management."},
    {"name": "Auction", "description": "Auction and bidding endpoints."},
    {"name": "Announcement", "description": "System announcements."},
    {"name": "Inventory", "description": "Inventory management."},
    {"name": "Equipment", "description": "Hero equipment management."},
    {"name": "Health", "description": "Healthcheck and monitoring."},
]

app = FastAPI(title="Hero Manager API", openapi_tags=tags_metadata)

# Rate limiter
limiter = Limiter(key_func=get_remote_address, default_limits=["10/second"])
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# CORS middleware (адаптовано для Godot та браузерів)
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins_list,  # Виправлено: використовуємо список з конфігу
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Обробники виключень
@app.exception_handler(StarletteHTTPException)
async def http_exception_handler(request: Request, exc: StarletteHTTPException):
    logging.error(f"HTTP error occurred: {exc.detail}")
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail},
    )

@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    logging.error(f"Validation error: {exc.errors()}")
    return JSONResponse(
        status_code=422,
        content={"detail": exc.errors()},
    )

@app.exception_handler(SQLAlchemyError)
async def sqlalchemy_exception_handler(request: Request, exc: SQLAlchemyError):
    logging.error(f"Database error: {exc}")
    return JSONResponse(
        status_code=500,
        content={"detail": "Database error"},
    )

@app.exception_handler(Exception)
async def unhandled_exception_handler(request: Request, exc: Exception):
    logging.exception("Unhandled error occurred")
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal Server Error"},
    )

# Підключення маршрутів
app.include_router(auth.router, prefix="/auth", tags=["Auth"])
app.include_router(hero.router, prefix="/heroes", tags=["Heroes"])
app.include_router(auction.router)
app.include_router(bid.router)
app.include_router(announcement.router)
app.include_router(inventory.router)
app.include_router(equipment.router)
app.include_router(workshop.router)

# Створення бази, якщо відсутня
async def create_database_if_not_exists():
    # Skip database creation for SQLite (used in testing)
    if settings.DATABASE_URL.startswith("sqlite"):
        return
    url = settings.DATABASE_URL
    if url.startswith("postgresql+asyncpg://"):
        url_asyncpg = url.replace("postgresql+asyncpg://", "postgresql://", 1)
    else:
        url_asyncpg = url
    parsed = urllib.parse.urlparse(url_asyncpg)
    db_name = parsed.path.lstrip("/")
    default_db = "postgres"

    conn = await asyncpg.connect(
        user=parsed.username,
        password=parsed.password,
        host=parsed.hostname,
        port=parsed.port or 5432,
        database=default_db
    )
    exists = await conn.fetchval(
        "SELECT 1 FROM pg_database WHERE datname = $1", db_name
    )
    if not exists:
        await conn.execute(f'CREATE DATABASE "{db_name}"')
    await conn.close()

# Події при старті додатку
@app.on_event("startup")
async def on_startup():
    await create_database_if_not_exists()
    await create_db_and_tables()
    # connect to Redis if configured (cache & pub/sub)
    if settings.REDIS_URL:
        await redis_cache.connect()
    # immediate sweep of expired auctions/lots before background loops
    async with AsyncSessionLocal() as session:
        await AuctionService(session).close_expired_auctions()
    asyncio.create_task(delete_old_heroes_task())
    asyncio.create_task(close_expired_auctions_task())

# Clean up database connections on shutdown
@app.on_event("shutdown")
async def on_shutdown():
    # clean up database engine
    await engine.dispose()
    # close redis if opened
    if settings.REDIS_URL:
        await redis_cache.close()

# Add health router
app.include_router(health_router)

# Add domain routers
app.include_router(raid_router)
app.include_router(craft_router)
app.include_router(pvp_router)
app.include_router(tournaments_router)
app.include_router(events_router)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",  # Виправлено: для запуску з кореня
        host=settings.HOST,
        port=settings.PORT,
        reload=True,
    )
