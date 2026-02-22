from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.session import get_session
from app.core.redis_cache import redis_cache

router = APIRouter(prefix="/health", tags=["Health"])

@router.get("/", summary="Readiness & Liveness check")
async def healthz(db: AsyncSession = Depends(get_session)):
    db_ok = False
    try:
        await db.execute(text("SELECT 1"))
        db_ok = True
    except:
        pass
    redis_ok = False
    try:
        await redis_cache.connect()
        await redis_cache.set("healthcheck", "ok", expire=2)
        val = await redis_cache.get("healthcheck")
        redis_ok = val == b"ok" or val == "ok"
    except:
        pass
    status = "ok" if db_ok and redis_ok else "error"
    return {"status": status, "db": db_ok, "redis": redis_ok} 