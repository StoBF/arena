"""
Premium Currency Service (Crystal Shop)
=========================================
Players buy premium crystals with real money via Stripe.
Crystals are used for:
  - Heal speedup (5 crystals/hour)
  - Hero generation boost (50/150/400 crystals for +5%/+15%/+30% power)
  - Craft speedup (3 crystals/hour)
  - Extra resurrection attempt (200 crystals, still 5% chance)
  - Extra daily quest slot (30 crystals)

Flow:
  1. Player selects package → POST /premium/checkout → Stripe Payment Intent
  2. Stripe webhook → payment_intent.succeeded → credit crystals
  3. Player spends crystals in-game → crystal balance decrements + transaction logged

Crystal packages are defined in CRYSTAL_PACKAGES constant in game_systems.py.
"""
from __future__ import annotations

import os
from datetime import datetime
from typing import Dict, List, Optional

from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.models.game_systems import (
    PremiumBalance, PremiumPurchase, PremiumTransaction,
    PurchaseStatus, CRYSTAL_PACKAGES, CRYSTAL_COSTS,
)


class PremiumCurrencyService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Crystal balance ───────────────────────────────────────────────────────
    async def get_balance(self, user_id: int) -> PremiumBalance:
        result = await self.db.execute(
            select(PremiumBalance).where(PremiumBalance.user_id == user_id)
        )
        bal = result.scalar_one_or_none()
        if not bal:
            bal = PremiumBalance(user_id=user_id, crystals=0)
            self.db.add(bal)
            await self.db.commit()
            await self.db.refresh(bal)
        return bal

    async def credit(
        self,
        user_id: int,
        amount:  int,
        reason:  str,
        ref_id:  Optional[str] = None,
    ) -> PremiumBalance:
        bal = await self.get_balance(user_id)
        bal.crystals     += amount
        bal.total_earned += amount
        bal.updated_at    = datetime.utcnow()

        tx = PremiumTransaction(
            user_id       = user_id,
            amount        = amount,
            reason        = reason,
            ref_id        = ref_id,
            balance_after = bal.crystals,
        )
        self.db.add(tx)
        await self.db.commit()
        await self.db.refresh(bal)
        return bal

    async def spend(
        self,
        user_id: int,
        amount:  int,
        reason:  str,
        ref_id:  Optional[str] = None,
    ) -> PremiumBalance:
        bal = await self.get_balance(user_id)
        if bal.crystals < amount:
            raise ValueError(
                f"Not enough crystals (need {amount}, have {bal.crystals})"
            )
        bal.crystals    -= amount
        bal.total_spent += amount
        bal.updated_at   = datetime.utcnow()

        tx = PremiumTransaction(
            user_id       = user_id,
            amount        = -amount,
            reason        = reason,
            ref_id        = ref_id,
            balance_after = bal.crystals,
        )
        self.db.add(tx)
        await self.db.commit()
        await self.db.refresh(bal)
        return bal

    # ── Stripe checkout ───────────────────────────────────────────────────────
    async def create_checkout_intent(
        self, user_id: int, package_id: str
    ) -> Dict:
        """
        Creates a Stripe Payment Intent for a crystal package.
        Returns client_secret for front-end confirmation.
        """
        package = next((p for p in CRYSTAL_PACKAGES if p["id"] == package_id), None)
        if not package:
            raise ValueError(f"Unknown package: {package_id}")

        stripe_key = os.environ.get("STRIPE_SECRET_KEY")
        if not stripe_key:
            raise ValueError("Stripe not configured (STRIPE_SECRET_KEY missing)")

        import stripe as stripe_sdk
        stripe_sdk.api_key = stripe_key

        amount_cents = int(package["usd"] * 100)

        # Ensure Stripe customer exists
        stripe_customer_id = await self._get_or_create_stripe_customer(user_id)

        intent = stripe_sdk.PaymentIntent.create(
            amount   = amount_cents,
            currency = "usd",
            customer = stripe_customer_id,
            metadata = {
                "user_id":        str(user_id),
                "package_id":     package_id,
                "crystals":       str(package["crystals"]),
                "bonus_crystals": str(package["bonus"]),
            },
            description = (
                f"Hero Manager – {package['crystals'] + package['bonus']} crystals "
                f"({package_id} pack)"
            ),
        )

        # Record pending purchase
        purchase = PremiumPurchase(
            user_id               = user_id,
            stripe_payment_intent = intent["id"],
            amount_usd            = package["usd"],
            crystals_granted      = package["crystals"],
            bonus_crystals        = package["bonus"],
            status                = PurchaseStatus.pending,
        )
        self.db.add(purchase)
        await self.db.commit()

        return {
            "client_secret":     intent["client_secret"],
            "payment_intent_id": intent["id"],
            "package":           package,
            "total_crystals":    package["crystals"] + package["bonus"],
        }

    # ── Stripe webhook handler ────────────────────────────────────────────────
    async def handle_stripe_webhook(
        self, payload: bytes, sig_header: str
    ) -> Dict:
        """
        Called by POST /premium/stripe-webhook.
        Verifies signature and credits crystals on payment_intent.succeeded.
        """
        stripe_key        = os.environ.get("STRIPE_SECRET_KEY")
        webhook_secret    = os.environ.get("STRIPE_WEBHOOK_SECRET")

        import stripe as stripe_sdk
        stripe_sdk.api_key = stripe_key

        try:
            event = stripe_sdk.Webhook.construct_event(
                payload, sig_header, webhook_secret
            )
        except stripe_sdk.error.SignatureVerificationError:
            raise ValueError("Invalid Stripe signature")

        if event["type"] != "payment_intent.succeeded":
            return {"status": "ignored", "event_type": event["type"]}

        intent   = event["data"]["object"]
        intent_id = intent["id"]
        metadata  = intent.get("metadata", {})

        user_id       = int(metadata.get("user_id", 0))
        crystals      = int(metadata.get("crystals", 0))
        bonus         = int(metadata.get("bonus_crystals", 0))
        package_id    = metadata.get("package_id", "")

        # Find purchase record
        result = await self.db.execute(
            select(PremiumPurchase).where(
                PremiumPurchase.stripe_payment_intent == intent_id
            )
        )
        purchase = result.scalar_one_or_none()
        if purchase and purchase.status == PurchaseStatus.completed:
            return {"status": "already_processed"}

        # Credit crystals
        total = crystals + bonus
        if user_id and total > 0:
            await self.credit(
                user_id = user_id,
                amount  = total,
                reason  = f"purchase:{package_id}",
                ref_id  = intent_id,
            )

        if purchase:
            purchase.status          = PurchaseStatus.completed
            purchase.stripe_charge_id = intent.get("latest_charge")
            purchase.completed_at    = datetime.utcnow()
            await self.db.commit()

        return {
            "status":      "credited",
            "user_id":     user_id,
            "crystals":    total,
            "package_id":  package_id,
        }

    # ── Transaction history ───────────────────────────────────────────────────
    async def get_transactions(
        self, user_id: int, limit: int = 30
    ) -> List[PremiumTransaction]:
        result = await self.db.execute(
            select(PremiumTransaction)
            .where(PremiumTransaction.user_id == user_id)
            .order_by(PremiumTransaction.created_at.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    # ── Hero generation boost ─────────────────────────────────────────────────
    async def apply_hero_gen_boost(
        self, user_id: int, tier: int
    ) -> Dict:
        """
        Deducts crystals and returns the bonus power multiplier.
        tier: 1 (+5%), 2 (+15%), 3 (+30%)
        """
        cost_key = f"hero_gen_boost_tier{tier}"
        if cost_key not in CRYSTAL_COSTS:
            raise ValueError(f"Invalid tier: {tier}")
        cost        = CRYSTAL_COSTS[cost_key]
        bonus_pct   = {1: 5, 2: 15, 3: 30}[tier]
        bonus_mult  = 1.0 + bonus_pct / 100.0

        await self.spend(user_id, cost, f"hero_gen_boost_tier{tier}")
        return {
            "tier":         tier,
            "crystals_spent": cost,
            "bonus_pct":    bonus_pct,
            "power_mult":   bonus_mult,
        }

    # ── Packages catalog (no auth needed) ────────────────────────────────────
    def get_packages(self) -> List[Dict]:
        return CRYSTAL_PACKAGES

    # ── Internal: Stripe customer ──────────────────────────────────────────────
    async def _get_or_create_stripe_customer(self, user_id: int) -> str:
        from app.database.models.user import User
        user = await self.db.get(User, user_id)
        if not user:
            raise ValueError("User not found")

        if getattr(user, "stripe_customer_id", None):
            return user.stripe_customer_id

        import stripe as stripe_sdk
        customer = stripe_sdk.Customer.create(
            email    = user.email,
            metadata = {"user_id": str(user_id)},
        )
        if hasattr(user, "stripe_customer_id"):
            user.stripe_customer_id = customer["id"]
            await self.db.commit()

        return customer["id"]
