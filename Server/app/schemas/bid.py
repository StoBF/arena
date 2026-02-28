from pydantic import BaseModel, Field, ConfigDict
from datetime import datetime
from typing import Optional
from decimal import Decimal

class BidCreate(BaseModel):
    auction_id: int = Field(...)
    amount: Decimal = Field(..., decimal_places=2)
    request_id: Optional[str] = Field(None, description="Idempotent request identifier (UUID)")

class BidOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    request_id: Optional[str] = Field(None)
    auction_id: int = Field(...)
    bidder_id: int = Field(...)
    amount: Decimal = Field(...)
    created_at: datetime = Field(...)
