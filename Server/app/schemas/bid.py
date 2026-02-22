from pydantic import BaseModel, Field
from datetime import datetime
from typing import Optional
from decimal import Decimal

class BidCreate(BaseModel):
    auction_id: int = Field(..., example=1)
    amount: Decimal = Field(..., example="600.00", decimal_places=2)
    request_id: Optional[str] = Field(None, example="550e8400-e29b-41d4-a716-446655440000", description="Idempotent request identifier (UUID)")

class BidOut(BaseModel):
    id: int = Field(..., example=1)
    request_id: Optional[str] = Field(None, example="550e8400-e29b-41d4-a716-446655440000")
    auction_id: int = Field(..., example=1)
    bidder_id: int = Field(..., example=3)
    amount: Decimal = Field(..., example="600.00")
    created_at: datetime = Field(..., example="2024-06-01T13:00:00Z")

    class Config:
        from_attributes = True
