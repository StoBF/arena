"""Battle Betting Router"""
from __future__ import annotations

from decimal import Decimal
from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.session import get_session
from app.auth import get_current_user_info
from app.services.betting_service import BettingService


router = APIRouter(prefix="/betting", tags=["Battle Betting"])


class CreateMarketIn(BaseModel):
    match_type:     str
    match_id:       str
    house_edge_pct: float = Field(0.05, ge=0.0, le=0.20)


class PlaceBetIn(BaseModel):
    side:   str
    amount: Decimal = Field(..., gt=0)


class SettleMarketIn(BaseModel):
    winner_side: str


def _market_dict(market, svc: BettingService) -> Dict:
    odds = svc.odds_display(market)
    return {
        "id":             market.id,
        "match_type":     market.match_type,
        "match_id":       market.match_id,
        "status":         market.status.value,
        "winner_ref":     market.winner_ref,
        "opens_at":       market.opens_at.isoformat(),
        "locks_at":       market.locks_at.isoformat() if market.locks_at else None,
        "settled_at":     market.settled_at.isoformat() if market.settled_at else None,
        "odds":           odds,
        "house_edge_pct": market.house_edge_pct,
    }


@router.post("/markets")
async def create_market(
    body:     CreateMarketIn,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    if user_info.get("role") not in ("admin", "moderator"):
        raise HTTPException(403, "Admin only")
    svc    = BettingService(db)
    market = await svc.create_market(body.match_type, body.match_id,
                                     house_edge_pct=body.house_edge_pct)
    return _market_dict(market, svc)


@router.get("/markets/by-match/{match_type}/{match_id}")
async def get_market_by_match(
    match_type: str,
    match_id:   str,
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc    = BettingService(db)
    market = await svc.get_market_by_match(match_type, match_id)
    if not market:
        raise HTTPException(404, "Market not found")
    return _market_dict(market, svc)


@router.get("/markets/{market_id}")
async def get_market(
    market_id: int,
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc    = BettingService(db)
    market = await svc.get_market(market_id)
    if not market:
        raise HTTPException(404, "Market not found")
    return _market_dict(market, svc)


@router.post("/markets/{market_id}/bet")
async def place_bet(
    market_id: int,
    body:      PlaceBetIn,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc = BettingService(db)
    try:
        bet = await svc.place_bet(market_id, user_info["user_id"], body.side, body.amount)
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    market = await svc.get_market(market_id)
    return {
        "bet_id":        bet.id,
        "side":          bet.side,
        "amount":        float(bet.amount),
        "placed_at":     bet.placed_at.isoformat(),
        "current_odds":  svc.odds_display(market),
    }


@router.post("/markets/{market_id}/lock")
async def lock_market(
    market_id: int,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    if user_info.get("role") not in ("admin", "moderator"):
        raise HTTPException(403, "Admin only")
    svc    = BettingService(db)
    market = await svc.lock_market(market_id)
    return {"status": market.status.value, "market_id": market_id}


@router.post("/markets/{market_id}/settle")
async def settle_market(
    market_id: int,
    body:      SettleMarketIn,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    if user_info.get("role") not in ("admin", "moderator"):
        raise HTTPException(403, "Admin only")
    svc = BettingService(db)
    return await svc.settle_market(market_id, body.winner_side)


@router.post("/markets/{market_id}/cancel")
async def cancel_market(
    market_id: int,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    if user_info.get("role") not in ("admin", "moderator"):
        raise HTTPException(403, "Admin only")
    svc = BettingService(db)
    await svc.cancel_market(market_id)
    return {"status": "cancelled", "market_id": market_id}


@router.get("/my-bets")
async def my_bets(
    limit:    int = Query(20, ge=1, le=100),
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc  = BettingService(db)
    bets = await svc.get_user_bets(user_info["user_id"], limit)
    return {
        "bets": [
            {"id": b.id, "market_id": b.market_id, "side": b.side,
             "amount": float(b.amount), "payout": float(b.payout) if b.payout else None,
             "is_winner": b.is_winner, "placed_at": b.placed_at.isoformat(),
             "settled_at": b.settled_at.isoformat() if b.settled_at else None}
            for b in bets
        ]
    }


@router.get("/markets/{market_id}/bets")
async def market_bets(
    market_id: int,
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc  = BettingService(db)
    bets = await svc.get_market_bets(market_id)
    return {
        "market_id": market_id,
        "bets": [
            {"bettor_id": b.bettor_id, "side": b.side,
             "amount": float(b.amount), "placed_at": b.placed_at.isoformat()}
            for b in bets
        ],
    }
