from pydantic import BaseModel
from typing import List, Dict, Any, Optional
from datetime import datetime

class EventDefinitionOut(BaseModel):
    id: int
    name: str
    schedule_cron: str
    rewards: List[Dict[str, Any]]

    class Config:
        orm_mode = True

class EventInstanceOut(BaseModel):
    id: int
    definition_id: int
    start_time: datetime
    end_time: datetime
    status: str
    participants: List[int]
    completed_at: Optional[datetime]

    class Config:
        orm_mode = True

class EventJoinIn(BaseModel):
    user_id: int 