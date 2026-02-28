from pydantic import BaseModel, Field, ConfigDict
from datetime import datetime
from typing import Optional

class ChatMessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    channel: str = Field(...)
    sender_id: int = Field(...)
    recipient_id: Optional[int] = Field(None)
    text: str = Field(...)
    created_at: datetime = Field(...)


class OfflineMessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    sender_id: int = Field(...)
    recipient_id: int = Field(...)
    text: str = Field(...)
    created_at: datetime = Field(...)
    delivered: bool = Field(...)
