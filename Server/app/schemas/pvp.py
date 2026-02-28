from pydantic import BaseModel, ConfigDict
from typing import List, Dict, Any, Optional
from datetime import datetime

class PvPMatchIn(BaseModel):
    player1_id: int
    player2_id: int

class PvPBattleEvent(BaseModel):
    actor_id: int
    action: str
    target_ids: List[int]
    value: Optional[int] = 0
    context: Any

class PvPBattleLogOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    match_id: int
    events: List[PvPBattleEvent]
    outcome: str
    created_at: datetime


class LeaderboardEntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    user_id: int
    rating: float
    wins: int
    losses: int
