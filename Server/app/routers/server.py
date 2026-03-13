from fastapi import APIRouter

from app.schemas.server_status import ServerStatusOut
from app.services.session_registry import active_session_registry


router = APIRouter(prefix="/server", tags=["Server"])


@router.get("/status", response_model=ServerStatusOut, summary="Lightweight server status")
async def server_status() -> ServerStatusOut:
    return ServerStatusOut(
        status="online",
        online_players=active_session_registry.online_players_count(),
    )
