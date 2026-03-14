import asyncio
import json
import logging

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.core.redis_pubsub import subscribe_auction_updates
from app.utils.jwt import get_user_id_from_token


router = APIRouter()
logger = logging.getLogger(__name__)


@router.websocket("/ws/auctions")
async def ws_auctions(websocket: WebSocket):
	token = websocket.query_params.get("token")
	user_id = get_user_id_from_token(token) if token else None
	if not user_id:
		await websocket.close(code=1008)
		return

	await websocket.accept()

	async def sender() -> None:
		async for event in subscribe_auction_updates():
			await websocket.send_text(json.dumps(event))

	send_task = asyncio.create_task(sender())
	try:
		while True:
			await websocket.receive_text()
	except WebSocketDisconnect:
		logger.info("[WS_AUCTIONS_DISCONNECT] user_id=%s", user_id)
	except Exception as exc:
		logger.exception("[WS_AUCTIONS_ERROR] user_id=%s error=%s", user_id, exc)
		try:
			await websocket.close(code=1011)
		except Exception:
			pass
	finally:
		send_task.cancel()