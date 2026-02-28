from pydantic import BaseModel, ConfigDict
from typing import List, Dict, Any, Optional
from datetime import datetime

class EventDefinitionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    schedule_cron: str
    rewards: List[Dict[str, Any]]


class EventInstanceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    definition_id: int
    start_time: datetime
    end_time: datetime
    status: str
    participants: List[int]
    completed_at: Optional[datetime]


class EventJoinIn(BaseModel):
    user_id: int 