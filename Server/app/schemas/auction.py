from pydantic import BaseModel, Field, field_validator, ConfigDict
from datetime import datetime
from typing import Optional
from decimal import Decimal
from app.core.enums import AuctionStatus

class AuctionCreate(BaseModel):
    item_id: int = Field(...)
    start_price: Decimal = Field(..., decimal_places=2)
    duration: int = Field(..., description="у годинах (max 24)")

    @field_validator('duration')
    def max_24h(cls, v):
        if v < 1 or v > 24:
            raise ValueError('duration must be between 1 and 24 hours')
        return v
    quantity: int = Field(1)

class AuctionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    item_id: int = Field(...)
    seller_id: int = Field(...)
    start_price: Decimal = Field(...)
    current_price: Decimal = Field(...)
    end_time: datetime = Field(...)
    status: AuctionStatus = Field(...)
    winner_id: Optional[int] = Field(None)
    quantity: int = Field(...)
    created_at: datetime = Field(...)


class AuctionListOut(AuctionOut):
    pass

class AuctionLotCreate(BaseModel):
    hero_id: int = Field(...)
    starting_price: Decimal = Field(..., decimal_places=2)
    buyout_price: Optional[Decimal] = Field(None, decimal_places=2)
    duration: int = Field(..., description="in hours, max 24")

    @field_validator('duration')
    def max_24h(cls, v):
        if v < 1 or v > 24:
            raise ValueError('duration must be between 1 and 24 hours')
        return v

class AuctionLotOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    hero_id: int = Field(...)
    seller_id: int = Field(...)
    starting_price: Decimal = Field(...)
    current_price: Decimal = Field(...)
    buyout_price: Optional[Decimal] = Field(None)
    end_time: datetime = Field(...)
    winner_id: Optional[int] = Field(None)
    status: AuctionStatus = Field(...)
    created_at: datetime = Field(...)


class CreateAuctionLot(BaseModel):
    # add fields as needed
    pass

class OutAuctionLot(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    # add other fields as needed

class BidCreate(BaseModel):
    auction_id: int = Field(...)
    amount: Decimal = Field(..., decimal_places=2)

class BidOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    auction_id: int = Field(...)
    bidder_id: int = Field(...)
    amount: Decimal = Field(...)
    created_at: datetime = Field(...)


class AutoBidCreate(BaseModel):
    auction_id: Optional[int] = Field(None)
    lot_id: Optional[int] = Field(None)
    max_amount: Decimal = Field(..., decimal_places=2)

class AutoBidOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    auction_id: Optional[int] = Field(None)
    lot_id: Optional[int] = Field(None)
    user_id: int = Field(...)
    max_amount: Decimal = Field(...)
    created_at: datetime = Field(...)

