from dotenv import load_dotenv
load_dotenv()  # тепер os.getenv() підхоплює ваш .env

import logging
import urllib.parse
import asyncpg
import asyncio
from contextlib import asynccontextmanager, suppress
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
from app.routers import auth, hero, auction, bid, announcement, inventory, equipment, chat
from app.tasks.cleanup import delete_old_heroes_task
from app.tasks.auctions import close_expired_auctions_task, run_auction_sweep_once
from app.routers.health import router as health_router
from app.routers.battle import router as battle_router
from app.routers.raid import router as raid_router
from app.routers.craft import router as craft_router
from app.routers.pvp import router as pvp_router
from app.routers.tournaments import router as tournaments_router
from app.routers.events import router as events_router
from app.routers.server import router as server_router
from app.routers.auctions_ws import router as auctions_ws_router

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

@asynccontextmanager
async def lifespan(app: FastAPI):
    await wait_for_postgres_ready()
    await create_database_if_not_exists()
    await create_db_and_tables()

    if settings.REDIS_URL:
        await redis_cache.connect()

    try:
        async with AsyncSessionLocal() as session:
            async with session.begin():
                await run_auction_sweep_once(session)
    except Exception:
        logging.exception("[AUCTION] startup sweep failed; continuing application startup")

    cleanup_task = asyncio.create_task(delete_old_heroes_task())
    auctions_task = asyncio.create_task(close_expired_auctions_task())
    app.state.cleanup_task = cleanup_task
    app.state.auctions_task = auctions_task

    try:
        yield
    finally:
        for task in (cleanup_task, auctions_task):
            task.cancel()
            with suppress(asyncio.CancelledError):
                await task

        await engine.dispose()

        if settings.REDIS_URL:
            await redis_cache.close()


app = FastAPI(title="Hero Manager API", openapi_tags=tags_metadata, lifespan=lifespan)

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

# ── Diagnostic middleware: log EVERY incoming request ──
@app.middleware("http")
async def log_all_requests(request: Request, call_next):
    logging.info("[INCOMING] %s %s  client=%s", request.method, request.url, request.client.host if request.client else "?")
    response = await call_next(request)
    # Keep ASCII-only marker to avoid cp1251 console encoding crashes on Windows.
    logging.info("[RESPONSE] %s %s -> %d", request.method, request.url.path, response.status_code)
    return response

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
app.include_router(hero.router)
app.include_router(auction.router)
app.include_router(bid.router)
app.include_router(announcement.router)
app.include_router(inventory.router)
app.include_router(equipment.router)
app.include_router(chat.router, tags=["Chat"])

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
        database=default_db,
        timeout=5,
    )
    exists = await conn.fetchval(
        "SELECT 1 FROM pg_database WHERE datname = $1", db_name
    )
    if not exists:
        await conn.execute(f'CREATE DATABASE "{db_name}"')
    await conn.close()


async def wait_for_postgres_ready() -> None:
    """
    Wait until PostgreSQL is ready to accept connections.
    This handles crash-recovery windows after unclean shutdowns.
    """
    if settings.DATABASE_URL.startswith("sqlite"):
        return

    url = settings.DATABASE_URL
    if url.startswith("postgresql+asyncpg://"):
        check_url = url.replace("postgresql+asyncpg://", "postgresql://", 1)
    else:
        check_url = url

    parsed = urllib.parse.urlparse(check_url)
    # Probe maintenance DB so readiness succeeds even before app DB is created.
    probe_db = "postgres"

    last_error: Exception | None = None
    for attempt in range(1, settings.DB_CONNECT_RETRIES + 1):
        try:
            conn = await asyncpg.connect(
                user=parsed.username,
                password=parsed.password,
                host=parsed.hostname,
                port=parsed.port or 5432,
                database=probe_db,
                timeout=5,
            )
            await conn.fetchval("SELECT 1")
            await conn.close()
            logging.info("[DB] PostgreSQL is ready (attempt %d)", attempt)
            return
        except Exception as exc:
            last_error = exc
            logging.warning(
                "[DB] PostgreSQL not ready yet (attempt %d/%d): %s",
                attempt,
                settings.DB_CONNECT_RETRIES,
                exc,
            )
            await asyncio.sleep(settings.DB_CONNECT_RETRY_DELAY_SECONDS)

    raise RuntimeError(f"PostgreSQL did not become ready in time: {last_error}")

# Add health router
app.include_router(health_router)

# Add domain routers
app.include_router(battle_router)
app.include_router(raid_router)
app.include_router(craft_router)
app.include_router(pvp_router)
app.include_router(tournaments_router)
app.include_router(events_router)
app.include_router(server_router)
app.include_router(auctions_ws_router, tags=["Auction WS"])

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",  # Виправлено: для запуску з кореня
        host=settings.HOST,
        port=settings.PORT,
        reload=True,
    )
