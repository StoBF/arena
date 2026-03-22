from pydantic import BaseModel, Field, ConfigDict, model_validator
from datetime import datetime
from typing import Optional
from decimal import Decimal

class BidCreate(BaseModel):
    auction_id: Optional[int] = Field(None, description="Item auction ID (mutually exclusive with lot_id)")
    lot_id: Optional[int] = Field(None, description="Hero auction lot ID (mutually exclusive with auction_id)")
    amount: Decimal = Field(..., decimal_places=2)
    request_id: Optional[str] = Field(None, description="Idempotent request identifier (UUID)")

    @model_validator(mode="after")
    def _exactly_one_target(self):
        has_auction = self.auction_id is not None
        has_lot = self.lot_id is not None
        if has_auction == has_lot:  # both set or both missing
            raise ValueError("Specify exactly one of auction_id or lot_id")
        return self

class BidOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    request_id: Optional[str] = Field(None)
    auction_id: Optional[int] = Field(None)
    lot_id: Optional[int] = Field(None)
    bidder_id: int = Field(...)
    amount: Decimal = Field(...)
    created_at: datetime = Field(...)
