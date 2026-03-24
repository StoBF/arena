"""
Currency Shop Router
=====================
Купівля ігрового золота за реальні гроші через Stripe.
Пакети та ціни: config/game_config.yaml → currency_shop.packages

GET  /currency-shop/packages          — список доступних пакетів
GET  /currency-shop/history           — історія покупок гравця
POST /currency-shop/checkout          — Stripe PaymentIntent (повертає client_secret)
POST /currency-shop/stripe-webhook    — обробка Stripe events (payment_intent.succeeded)
POST /currency-shop/hero-gen-boost    — витратити золото на посилення генерації героя
"""
from __future__ import annotations

from typing import Any, Dict

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import get_current_user_info
from app.core.game_config import cfg
from app.database.session import get_session
from app.services.currency_shop_service import currency_shop_service


router = APIRouter(prefix="/currency-shop", tags=["Currency Shop"])


# ── Request / Response schemas ────────────────────────────────────────────────

class CheckoutIn(BaseModel):
    package_id: str = Field(..., description="Package ID from /packages list, e.g. 'starter'")


class HeroGenBoostIn(BaseModel):
    tier: int = Field(..., ge=1, le=3, description="1 = +5%, 2 = +15%, 3 = +30%")


# ── Endpoints ──────────────────────────────────────────────────────────────────

@router.get("/packages")
async def list_packages() -> Dict[str, Any]:
    """
    Список пакетів золота для покупки.
    Всі ціни та кількість налаштовуються в game_config.yaml.
    """
    packages = currency_shop_service.list_packages()
    return {
        "packages": packages,
        "note": "All prices in USD. Gold is the only in-game currency.",
    }


@router.post("/checkout")
async def create_checkout(
    body:      CheckoutIn,
    user_info: dict = Depends(get_current_user_info),
    db:        AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    """
    Створює Stripe PaymentIntent та повертає client_secret для клієнтської оплати.
    Після успішної оплати Stripe webhook автоматично нараховує золото.
    """
    try:
        return await currency_shop_service.create_payment_intent(
            db, user_info["user_id"], body.package_id
        )
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    except RuntimeError as exc:
        raise HTTPException(503, str(exc))


@router.post("/stripe-webhook")
async def stripe_webhook(
    request: Request,
    db:      AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    """
    Stripe webhook endpoint.
    Зареєструй цей URL в Stripe Dashboard → Webhooks.
    Events: payment_intent.succeeded, payment_intent.payment_failed
    """
    payload    = await request.body()
    sig_header = request.headers.get("stripe-signature", "")
    try:
        return await currency_shop_service.handle_webhook(db, payload, sig_header)
    except ValueError as exc:
        raise HTTPException(400, str(exc))
    except RuntimeError as exc:
        raise HTTPException(503, str(exc))


@router.get("/history")
async def purchase_history(
    user_info: dict = Depends(get_current_user_info),
    db:        AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    """Повертає останні 20 покупок золота гравця."""
    purchases = await currency_shop_service.get_purchase_history(
        db, user_info["user_id"]
    )
    return {
        "purchases": [
            {
                "id":           p.id,
                "package_id":   p.package_id,
                "gold_granted": p.gold_granted,
                "bonus_gold":   p.bonus_gold,
                "total_gold":   p.gold_granted + p.bonus_gold,
                "amount_usd":   float(p.amount_usd),
                "status":       p.status.value,
                "created_at":   p.created_at.isoformat(),
                "completed_at": p.completed_at.isoformat() if p.completed_at else None,
            }
            for p in purchases
        ]
    }


@router.post("/hero-gen-boost")
async def hero_gen_boost(
    body:      HeroGenBoostIn,
    user_info: dict = Depends(get_current_user_info),
    db:        AsyncSession = Depends(get_session),
) -> Dict[str, Any]:
    """
    Витратити золото для посилення наступної генерації героя.
    Tier 1: +5% потужності, Tier 2: +15%, Tier 3: +30%.
    Вартість налаштовується в game_config.yaml → hero_generation.tier_boost.
    """
    from app.database.models.user import User
    tier = body.tier
    cost = cfg.hero_generation.tier_cost(tier)
    boost = cfg.hero_generation.tier_power_boost(tier)

    user = await db.get(User, user_info["user_id"])
    if not user:
        raise HTTPException(404, "User not found")
    if float(user.balance or 0) < cost:
        raise HTTPException(400, f"Insufficient gold. Need {cost}, have {float(user.balance or 0)}")

    user.balance = float(user.balance) - cost
    await db.commit()

    return {
        "tier":          tier,
        "cost_gold":     cost,
        "power_boost_pct": boost,
        "balance_after": float(user.balance),
        "note":          f"Next hero generation will be {boost}% stronger.",
    }
