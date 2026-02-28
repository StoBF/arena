from pydantic import BaseModel, ConfigDict
from enum import Enum

class ResourceType(str, Enum):
    PvE = "PvE"
    PvP = "PvP"

class GameResourceOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    type: ResourceType
    source: str
    description: str
