"""Premium Currency Router"""
from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.session import get_session
from app.auth import get_current_user_info
from app.services.premium_currency_service import PremiumCurrencyService


router = APIRouter(prefix="/premium", tags=["Premium Currency"])


class CheckoutIn(BaseModel):
    package_id: str


class SpendIn(BaseModel):
    amount: int = Field(..., ge=1)
    reason: str


@router.get("/packages")
async def list_packages() -> Dict[str, Any]:
    from app.database.models.game_systems import CRYSTAL_PACKAGES, CRYSTAL_COSTS
    return {"packages": CRYSTAL_PACKAGES, "crystal_costs": CRYSTAL_COSTS}


@router.get("/balance")
async def get_balance(
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    bal = await PremiumCurrencyService(db).get_balance(user_info["user_id"])
    return {
        "crystals":     bal.crystals,
        "total_earned": bal.total_earned,
        "total_spent":  bal.total_spent,
        "updated_at":   bal.updated_at.isoformat(),
    }


@router.get("/transactions")
async def transaction_history(
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc = PremiumCurrencyService(db)
    txs = await svc.get_transactions(user_info["user_id"])
    return {
        "transactions": [
            {"id": t.id, "amount": t.amount, "reason": t.reason,
             "balance_after": t.balance_after, "created_at": t.created_at.isoformat()}
            for t in txs
        ]
    }


@router.post("/checkout")
async def create_checkout(
    body:      CheckoutIn,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    try:
        return await PremiumCurrencyService(db).create_checkout_intent(
            user_info["user_id"], body.package_id
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc))


@router.post("/stripe-webhook")
async def stripe_webhook(
    request: Request,
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    payload    = await request.body()
    sig_header = request.headers.get("stripe-signature", "")
    try:
        return await PremiumCurrencyService(db).handle_stripe_webhook(payload, sig_header)
    except ValueError as exc:
        raise HTTPException(400, str(exc))


@router.post("/hero-gen-boost/{tier}")
async def hero_gen_boost(
    tier:      int,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    if tier not in (1, 2, 3):
        raise HTTPException(400, "Tier must be 1, 2, or 3")
    try:
        return await PremiumCurrencyService(db).apply_hero_gen_boost(user_info["user_id"], tier)
    except ValueError as exc:
        raise HTTPException(400, str(exc))


@router.post("/spend")
async def spend_crystals(
    body:      SpendIn,
    user_info: dict = Depends(get_current_user_info),
    db: AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    svc = PremiumCurrencyService(db)
    try:
        bal = await svc.spend(user_info["user_id"], body.amount, body.reason)
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    return {"crystals_remaining": bal.crystals}
