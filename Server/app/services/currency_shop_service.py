"""
Currency Shop Service
======================
Купівля ігрового золота за реальні гроші через Stripe.
Пакети налаштовуються в config/game_config.yaml → currency_shop.packages
"""
from __future__ import annotations

import os
from datetime import datetime
from typing import Any, Dict, List, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.game_config import cfg
from app.database.models.game_systems import CurrencyPurchase, PurchaseStatus


class CurrencyShopService:

    # ── Packages ─────────────────────────────────────────────────────────────

    def list_packages(self) -> List[Dict]:
        """Повертає список доступних пакетів золота (з конфігу)."""
        return cfg.currency_shop.packages

    def get_package(self, package_id: str) -> Optional[Dict]:
        return cfg.currency_shop.get_package(package_id)

    # ── Stripe Payment Intent ─────────────────────────────────────────────────

    async def create_payment_intent(
        self,
        db: AsyncSession,
        user_id: int,
        package_id: str,
    ) -> Dict[str, Any]:
        """
        Створює Stripe PaymentIntent та запис CurrencyPurchase у статусі pending.
        Повертає {client_secret, purchase_id, package}.
        """
        import stripe  # noqa: PLC0415

        pkg = cfg.currency_shop.get_package(package_id)
        if not pkg:
            raise ValueError(f"Unknown package: {package_id}")

        stripe.api_key = os.environ.get("STRIPE_SECRET_KEY", "")
        if not stripe.api_key:
            raise RuntimeError("STRIPE_SECRET_KEY not configured")

        amount_cents = int(round(pkg["usd_price"] * 100))
        intent = stripe.PaymentIntent.create(
            amount=amount_cents,
            currency="usd",
            metadata={"user_id": user_id, "package_id": package_id},
        )

        purchase = CurrencyPurchase(
            user_id=user_id,
            package_id=package_id,
            stripe_payment_intent=intent["id"],
            amount_usd=pkg["usd_price"],
            gold_granted=pkg["gold"],
            bonus_gold=pkg.get("bonus_gold", 0),
            status=PurchaseStatus.pending,
        )
        db.add(purchase)
        await db.commit()
        await db.refresh(purchase)

        return {
            "client_secret": intent["client_secret"],
            "purchase_id": purchase.id,
            "package": pkg,
        }

    # ── Stripe Webhook ────────────────────────────────────────────────────────

    async def handle_webhook(
        self,
        db: AsyncSession,
        payload: bytes,
        sig_header: str,
    ) -> Dict[str, str]:
        """
        Обробляє Stripe webhook. Нараховує золото при payment_intent.succeeded.
        """
        import stripe  # noqa: PLC0415

        webhook_secret = os.environ.get("STRIPE_WEBHOOK_SECRET", "")
        if not webhook_secret:
            raise RuntimeError("STRIPE_WEBHOOK_SECRET not configured")

        stripe.api_key = os.environ.get("STRIPE_SECRET_KEY", "")
        try:
            event = stripe.Webhook.construct_event(payload, sig_header, webhook_secret)
        except stripe.error.SignatureVerificationError:
            raise ValueError("Invalid Stripe signature")

        if event["type"] == "payment_intent.succeeded":
            intent = event["data"]["object"]
            await self._fulfill_purchase(db, intent)

        elif event["type"] == "payment_intent.payment_failed":
            intent = event["data"]["object"]
            await self._mark_failed(db, intent["id"])

        return {"status": "ok"}

    async def _fulfill_purchase(
        self,
        db: AsyncSession,
        intent: Dict,
    ) -> None:
        from app.database.models.user import User  # lazy

        result = await db.execute(
            select(CurrencyPurchase).where(
                CurrencyPurchase.stripe_payment_intent == intent["id"],
                CurrencyPurchase.status == PurchaseStatus.pending,
            )
        )
        purchase = result.scalar_one_or_none()
        if not purchase:
            return  # already processed or unknown

        total_gold = purchase.gold_granted + purchase.bonus_gold

        # Credit user's gold balance
        user_res = await db.execute(select(User).where(User.id == purchase.user_id))
        user = user_res.scalar_one_or_none()
        if user:
            user.balance = float(user.balance or 0) + total_gold

        purchase.status = PurchaseStatus.completed
        purchase.stripe_charge_id = intent.get("latest_charge")
        purchase.completed_at = datetime.utcnow()
        await db.commit()

    async def _mark_failed(self, db: AsyncSession, intent_id: str) -> None:
        result = await db.execute(
            select(CurrencyPurchase).where(
                CurrencyPurchase.stripe_payment_intent == intent_id
            )
        )
        purchase = result.scalar_one_or_none()
        if purchase and purchase.status == PurchaseStatus.pending:
            purchase.status = PurchaseStatus.failed
            await db.commit()

    # ── History ───────────────────────────────────────────────────────────────

    async def get_purchase_history(
        self,
        db: AsyncSession,
        user_id: int,
        limit: int = 20,
    ) -> List[CurrencyPurchase]:
        result = await db.execute(
            select(CurrencyPurchase)
            .where(CurrencyPurchase.user_id == user_id)
            .order_by(CurrencyPurchase.created_at.desc())
            .limit(limit)
        )
        return list(result.scalars().all())


currency_shop_service = CurrencyShopService()
