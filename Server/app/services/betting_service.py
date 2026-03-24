"""
Battle Betting Service
=======================
Players bet on any live battle or PvP match.
Odds are parimutuel (pool-based), not fixed.
House takes 5% of the losing pool.

Flow:
  1. POST /betting/market/create → create market for a match
  2. POST /betting/bet → place a bet on side A or B
  3. Battle finishes → router calls settle_market(market_id, winner)
  4. Winners receive payout proportional to their share of the winning pool
     multiplied by the losing pool (minus house edge).
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal
from typing import Dict, List, Optional

from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.database.models.game_systems import (
    BettingMarket, MatchBet, BetStatus,
)


class BettingService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ── Create market ─────────────────────────────────────────────────────────
    async def create_market(
        self,
        match_type: str,
        match_id:   str,
        locks_at:   Optional[datetime] = None,
        house_edge_pct: Optional[float] = None,
    ) -> BettingMarket:
        """house_edge_pct defaults to game_config.yaml → betting.house_edge_pct"""
        from app.core.game_config import cfg
        if house_edge_pct is None:
            house_edge_pct = cfg.betting.house_edge_pct
        # Idempotent
        result = await self.db.execute(
            select(BettingMarket).where(
                and_(BettingMarket.match_type == match_type,
                     BettingMarket.match_id   == match_id)
            )
        )
        existing = result.scalar_one_or_none()
        if existing:
            return existing

        market = BettingMarket(
            match_type     = match_type,
            match_id       = str(match_id),
            status         = BetStatus.open,
            locks_at       = locks_at,
            house_edge_pct = house_edge_pct,
        )
        self.db.add(market)
        await self.db.commit()
        await self.db.refresh(market)
        return market

    # ── Place bet ─────────────────────────────────────────────────────────────
    async def place_bet(
        self,
        market_id: int,
        bettor_id: int,
        side:      str,     # "A" | "B"
        amount:    Decimal,
    ) -> MatchBet:
        market = await self.db.get(BettingMarket, market_id)
        if not market:
            raise ValueError("Betting market not found")
        if market.status != BetStatus.open:
            raise ValueError(f"Market is {market.status.value}, not accepting bets")

        # Check balance
        from app.database.models.user import User
        user = await self.db.get(User, bettor_id)
        if not user or float(user.balance or 0) < float(amount):
            raise ValueError("Insufficient balance")

        # Deduct balance
        user.balance = float(user.balance) - float(amount)

        # Record bet
        bet = MatchBet(
            market_id = market_id,
            bettor_id = bettor_id,
            side      = side.upper(),
            amount    = amount,
        )
        self.db.add(bet)

        # Update market pools
        market.total_pool = market.total_pool + amount
        if side.upper() == "A":
            market.side_a_pool = market.side_a_pool + amount
        else:
            market.side_b_pool = market.side_b_pool + amount

        await self.db.commit()
        await self.db.refresh(bet)
        return bet

    # ── Lock market (fight started) ───────────────────────────────────────────
    async def lock_market(self, market_id: int) -> BettingMarket:
        market = await self.db.get(BettingMarket, market_id)
        if market:
            market.status   = BetStatus.locked
            market.locks_at = datetime.utcnow()
            await self.db.commit()
        return market

    # ── Settle market (fight ended) ───────────────────────────────────────────
    async def settle_market(
        self,
        market_id:  int,
        winner_side: str,    # "A" | "B"
    ) -> Dict:
        market = await self.db.get(BettingMarket, market_id)
        if not market:
            raise ValueError("Market not found")
        if market.status == BetStatus.settled:
            return {"already_settled": True}

        winner_side = winner_side.upper()
        market.winner_ref  = winner_side
        market.status      = BetStatus.settled
        market.settled_at  = datetime.utcnow()

        # Load all bets
        result = await self.db.execute(
            select(MatchBet).where(MatchBet.market_id == market_id)
        )
        bets: List[MatchBet] = list(result.scalars().all())

        winning_bets = [b for b in bets if b.side == winner_side]
        losing_pool  = float(
            market.side_b_pool if winner_side == "A" else market.side_a_pool
        )
        winning_pool = float(
            market.side_a_pool if winner_side == "A" else market.side_b_pool
        )

        # House takes edge from losing pool
        house_take   = losing_pool * market.house_edge_pct
        distributable = losing_pool - house_take

        total_payouts = 0.0
        from app.database.models.user import User

        for bet in bets:
            if bet.side != winner_side:
                # Loser: nothing back
                bet.is_winner  = False
                bet.payout     = Decimal("0")
                bet.settled_at = datetime.utcnow()
                continue

            bet.is_winner  = True
            bet.settled_at = datetime.utcnow()

            if winning_pool > 0:
                share   = float(bet.amount) / winning_pool
                profit  = distributable * share
                payout  = float(bet.amount) + profit
            else:
                payout  = float(bet.amount)  # refund if no one bet other side

            bet.payout = Decimal(str(round(payout, 2)))
            total_payouts += payout

            # Credit winner
            user = await self.db.get(User, bet.bettor_id)
            if user:
                user.balance = float(user.balance or 0) + payout

        await self.db.commit()
        return {
            "market_id":    market_id,
            "winner_side":  winner_side,
            "total_pool":   float(market.total_pool),
            "house_take":   house_take,
            "total_payouts":total_payouts,
            "bet_count":    len(bets),
        }

    # ── Cancel market (refund all) ────────────────────────────────────────────
    async def cancel_market(self, market_id: int) -> None:
        market = await self.db.get(BettingMarket, market_id)
        if not market or market.status == BetStatus.settled:
            return
        market.status = BetStatus.cancelled

        result = await self.db.execute(
            select(MatchBet).where(MatchBet.market_id == market_id)
        )
        from app.database.models.user import User
        for bet in result.scalars().all():
            user = await self.db.get(User, bet.bettor_id)
            if user:
                user.balance = float(user.balance or 0) + float(bet.amount)
            bet.payout     = bet.amount
            bet.is_winner  = None
            bet.settled_at = datetime.utcnow()

        await self.db.commit()

    # ── Read ──────────────────────────────────────────────────────────────────
    async def get_market(self, market_id: int) -> Optional[BettingMarket]:
        return await self.db.get(BettingMarket, market_id)

    async def get_market_by_match(
        self, match_type: str, match_id: str
    ) -> Optional[BettingMarket]:
        result = await self.db.execute(
            select(BettingMarket).where(
                and_(BettingMarket.match_type == match_type,
                     BettingMarket.match_id   == str(match_id))
            )
        )
        return result.scalar_one_or_none()

    async def get_user_bets(
        self, user_id: int, limit: int = 20
    ) -> List[MatchBet]:
        result = await self.db.execute(
            select(MatchBet)
            .where(MatchBet.bettor_id == user_id)
            .order_by(MatchBet.placed_at.desc())
            .limit(limit)
        )
        return list(result.scalars().all())

    async def get_market_bets(self, market_id: int) -> List[MatchBet]:
        result = await self.db.execute(
            select(MatchBet).where(MatchBet.market_id == market_id)
        )
        return list(result.scalars().all())

    def odds_display(self, market: BettingMarket) -> Dict:
        """Return implied odds for UI display."""
        a = float(market.side_a_pool)
        b = float(market.side_b_pool)
        total = a + b
        if total == 0:
            return {"side_a_payout_mult": 2.0, "side_b_payout_mult": 2.0}
        # Payout multiplier = total_pool / own_pool (minus house edge)
        edge = market.house_edge_pct
        a_mult = (total * (1 - edge)) / a if a > 0 else 99.0
        b_mult = (total * (1 - edge)) / b if b > 0 else 99.0
        return {
            "side_a_pool":         round(a, 2),
            "side_b_pool":         round(b, 2),
            "side_a_payout_mult":  round(a_mult, 2),
            "side_b_payout_mult":  round(b_mult, 2),
            "total_pool":          round(total, 2),
        }
