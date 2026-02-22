from pydantic import BaseModel
from enum import Enum

class ResourceType(str, Enum):
    PvE = "PvE"
    PvP = "PvP"

class GameResourceOut(BaseModel):
    id: int
    name: str
    type: ResourceType
    source: str
    description: str

    class Config:
        orm_mode = True 