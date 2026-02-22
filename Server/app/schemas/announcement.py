from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional

class AnnouncementCreate(BaseModel):
    message: str = Field(..., example="Server maintenance at 10 PM UTC.")

class AnnouncementOut(BaseModel):
    id: int = Field(..., example=1)
    message: str = Field(..., example="Server maintenance at 10 PM UTC.")
    author_id: Optional[int] = Field(None, example=42)
    created_at: Optional[datetime] = Field(None, example="2024-06-01T09:00:00Z")

    class Config:
        from_attributes = True