from sqlalchemy import Column, Integer, String, Enum
from app.database.models.models import Base
import enum

class ResourceType(enum.Enum):
    PvE = "PvE"
    PvP = "PvP"

class GameResource(Base):
    __tablename__ = "resources"
    id = Column(Integer, primary_key=True)
    name = Column(String, unique=True)
    type = Column(Enum(ResourceType))  # 'PvE' або 'PvP'
    source = Column(String)            # Наприклад, "raid_boss", "arena", тощо
    description = Column(String, default="") 