from datetime import datetime
from typing import List, Dict, Any
from random import random
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.database.models.models import PvPMatch, PvPBattleLog, LeaderboardEntry
from app.services.actions import simulate_pvp_battle  # you should implement a generator returning (events, winner_id)
from app.services.inventory import StashService  # stash persistence via StashService

# Configurable parameters with fallbacks to settings
ELO_K_FACTOR = getattr(settings, "PVP_ELO_K_FACTOR", 32.0)
MODULE_DROP_CHANCE = getattr(settings, "PVP_MODULE_DROP_CHANCE", 0.1)
RECIPE_DROP_CHANCE = getattr(settings, "PVP_RECIPE_DROP_CHANCE", 0.02)

class PvpService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def run_match(self, match_id: int) -> PvPBattleLog:
        """
        Execute a PvP match by simulating battle, persisting a log, granting rewards, and updating ratings.
        """
        match = await self.db.get(PvPMatch, match_id)
        # simulate the battle, get event list and winner user_id (None on draw)
        events, winner_id = await simulate_pvp_battle(self.db, match.player1_id, match.player2_id)
        match.winner_id = winner_id
        match.finished_at = datetime.utcnow()
        # determine outcome string
        if winner_id == match.player1_id:
            outcome = "player1_win"
        elif winner_id == match.player2_id:
            outcome = "player2_win"
        else:
            outcome = "draw"
        log = PvPBattleLog(match_id=match.id, events=events, outcome=outcome)
        self.db.add(log)

        # roll and persist PvP reward drops via StashService
        if winner_id:
            rewards: List[Dict[str, Any]] = []
            if random() < MODULE_DROP_CHANCE:
                rewards.append({"type": "module", "id": settings.PVP_MODULE_ITEM_ID, "qty": 1})
            if random() < RECIPE_DROP_CHANCE:
                rewards.append({"type": "recipe", "id": settings.PVP_RECIPE_ITEM_ID, "qty": 1})
            stash_service = StashService(self.db)
            for r in rewards:
                # only id and qty matter; StashService handles the rest
                await stash_service.add_to_stash(winner_id, r["id"], r["qty"])

        # update leaderboard ratings and win/loss
        await self.update_leaderboard(match.player1_id, match.player2_id, winner_id)
        await self.db.commit()
        return log

    async def update_leaderboard(self, p1_id: int, p2_id: int, winner_id: int) -> None:
        """
        Apply Elo rating adjustments and increment wins/losses for both players.
        """
        # load entries (create if missing)
        e1 = await self.db.get(LeaderboardEntry, p1_id)
        if not e1:
            e1 = LeaderboardEntry(user_id=p1_id)
            self.db.add(e1)
        e2 = await self.db.get(LeaderboardEntry, p2_id)
        if not e2:
            e2 = LeaderboardEntry(user_id=p2_id)
            self.db.add(e2)

        # expected scores
        r1 = 10 ** (e1.rating / 400)
        r2 = 10 ** (e2.rating / 400)
        exp1 = r1 / (r1 + r2)
        exp2 = r2 / (r1 + r2)

        # actual scores
        if winner_id == p1_id:
            score1, score2 = 1.0, 0.0
        elif winner_id == p2_id:
            score1, score2 = 0.0, 1.0
        else:
            score1 = score2 = 0.5

        # update ratings
        e1.rating += ELO_K_FACTOR * (score1 - exp1)
        e2.rating += ELO_K_FACTOR * (score2 - exp2)

        # update W/L
        e1.wins += int(score1)
        e1.losses += int(1 - score1)
        e2.wins += int(score2)
        e2.losses += int(1 - score2)

        # flush entries
        await self.db.flush()

    async def create_match(self, p1_id: int, p2_id: int) -> PvPMatch:
        """
        Create a new PvPMatch record for the two players.
        """
        match = PvPMatch(player1_id=p1_id, player2_id=p2_id)
        self.db.add(match)
        await self.db.flush()
        return match 