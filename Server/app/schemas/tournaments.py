from pydantic import BaseModel, ConfigDict
from typing import List, Dict, Any, Optional
from datetime import datetime

class TournamentCreateIn(BaseModel):
    template_id: int
    user_ids: List[int]

class TournamentOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    template_id: int
    participants: List[int]
    bracket: Dict[str, Any]
    status: str
    created_at: datetime
    completed_at: Optional[datetime] = None


class MatchAdvanceIn(BaseModel):
    round_no: int
    match_no: int
    winner_id: int 