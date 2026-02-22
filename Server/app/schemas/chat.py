from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional

class ChatMessageOut(BaseModel):
    id: int = Field(..., example=1)
    channel: str = Field(..., example="general")
    sender_id: int = Field(..., example=2)
    recipient_id: Optional[int] = Field(None, example=None)
    text: str = Field(..., example="Hello, world!")
    created_at: datetime = Field(..., example="2024-06-01T14:00:00Z")

    class Config:
        from_attributes = True

class OfflineMessageOut(BaseModel):
    id: int = Field(..., example=1)
    sender_id: int = Field(..., example=2)
    recipient_id: int = Field(..., example=3)
    text: str = Field(..., example="You missed this message!")
    created_at: datetime = Field(..., example="2024-06-01T14:00:00Z")
    delivered: bool = Field(..., example=False)

    class Config:
        from_attributes = True 