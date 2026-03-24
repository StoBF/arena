from sqlalchemy import Column, Integer, String, Enum as SAEnum
from app.database.base import Base
import enum


class ResourceType(enum.Enum):
    PvE   = "PvE"
    PvP   = "PvP"
    Boss  = "Boss"
    Craft = "Craft"


class ResourceCategory(str, enum.Enum):
    basic        = "basic"
    structural   = "structural"
    energetic    = "energetic"
    bio          = "bio"
    raid_rare    = "raid_rare"
    intermediate = "intermediate"


class GameResource(Base):
    __tablename__ = "resources"

    id          = Column(Integer, primary_key=True)
    code        = Column(String(64),  unique=True, nullable=False, index=True)
    name        = Column(String(128), nullable=False)
    category    = Column(SAEnum(ResourceCategory, name="resource_category"),
                         nullable=False, default=ResourceCategory.basic)
    source      = Column(String(128), default="")
    description = Column(String(512), default="")
