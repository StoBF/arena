from datetime import datetime
from typing import List, Dict, Any
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.database.models.tournament import TournamentTemplate, TournamentInstance
from app.services.bracket import build_bracket, update_bracket, is_tournament_complete

class TournamentService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create_tournament(self, template_id: int, user_ids: List[int]) -> TournamentInstance:
        """
        Create a new tournament instance based on a template and participant list.
        """
        tmpl = await self.db.get(TournamentTemplate, template_id)
        bracket: Dict[str, Any] = build_bracket(user_ids, tmpl.format)
        inst = TournamentInstance(
            template_id=tmpl.id,
            participants=user_ids,
            bracket=bracket,
            status=getattr(settings, "TOURNAMENT_INITIAL_STATUS", "active"),
            created_at=datetime.utcnow(),
        )
        self.db.add(inst)
        await self.db.commit()
        await self.db.refresh(inst)
        return inst

    async def advance_match(
        self,
        instance_id: int,
        round_no: int,
        match_no: int,
        winner_id: int,
    ) -> TournamentInstance:
        """
        Record the outcome of a single match and advance the tournament bracket.
        """
        inst = await self.db.get(TournamentInstance, instance_id)
        inst.bracket = update_bracket(inst.bracket, round_no, match_no, winner_id)
        if is_tournament_complete(inst.bracket):
            inst.status = getattr(settings, "TOURNAMENT_COMPLETED_STATUS", "completed")
            inst.completed_at = datetime.utcnow()
        await self.db.commit()
        await self.db.refresh(inst)
        return inst 