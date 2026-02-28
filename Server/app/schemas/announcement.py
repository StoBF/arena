from pydantic import BaseModel, Field, ConfigDict
from datetime import datetime
from typing import Optional

class AnnouncementCreate(BaseModel):
    message: str = Field(...)

class AnnouncementOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    message: str = Field(...)
    author_id: Optional[int] = Field(None)
    created_at: Optional[datetime] = Field(None)
