from pydantic import BaseModel, Field, validator
from datetime import datetime
from typing import Optional
from decimal import Decimal
from app.core.enums import AuctionStatus

class AuctionCreate(BaseModel):
    item_id: int = Field(..., example=101)
    start_price: Decimal = Field(..., example="500.00", decimal_places=2)
    duration: int = Field(..., example=24, description="у годинах (max 24)")

    @validator('duration')
    def max_24h(cls, v):
        if v < 1 or v > 24:
            raise ValueError('duration must be between 1 and 24 hours')
        return v
    quantity: int = Field(1, example=1)

class AuctionOut(BaseModel):
    id: int = Field(..., example=1)
    item_id: int = Field(..., example=101)
    seller_id: int = Field(..., example=5)
    start_price: Decimal = Field(..., example="500.00")
    current_price: Decimal = Field(..., example="750.00")
    end_time: datetime = Field(..., example="2024-06-01T12:00:00Z")
    status: AuctionStatus = Field(..., example=AuctionStatus.ACTIVE)
    winner_id: Optional[int] = Field(None, example=None)
    quantity: int = Field(..., example=1)
    created_at: datetime = Field(..., example="2024-05-31T12:00:00Z")

    class Config:
        from_attributes = True

class AuctionListOut(AuctionOut):
    pass

class AuctionLotCreate(BaseModel):
    hero_id: int = Field(..., example=10)
    starting_price: Decimal = Field(..., example="1000.00", decimal_places=2)
    buyout_price: Optional[Decimal] = Field(None, example="2000.00", decimal_places=2)
    duration: int = Field(..., example=24, description="in hours, max 24")

    @validator('duration')
    def max_24h(cls, v):
        if v < 1 or v > 24:
            raise ValueError('duration must be between 1 and 24 hours')
        return v

class AuctionLotOut(BaseModel):
    id: int = Field(..., example=1)
    hero_id: int = Field(..., example=10)
    seller_id: int = Field(..., example=5)
    starting_price: Decimal = Field(..., example="1000.00")
    current_price: Decimal = Field(..., example="1200.00")
    buyout_price: Optional[Decimal] = Field(None, example="2000.00")
    end_time: datetime = Field(...)
    winner_id: Optional[int] = Field(None, example=None)
    status: AuctionStatus = Field(..., example=AuctionStatus.ACTIVE)
    created_at: datetime = Field(...)

    class Config:
        from_attributes = True

class CreateAuctionLot(BaseModel):
    # add fields as needed
    pass

class OutAuctionLot(BaseModel):
    id: int = Field(..., example=1)
    # add other fields as needed

    class Config:
        from_attributes = True

class BidCreate(BaseModel):
    auction_id: int = Field(..., example=1)
    amount: Decimal = Field(..., example="1000.00", decimal_places=2)

class BidOut(BaseModel):
    id: int = Field(..., example=1)
    auction_id: int = Field(..., example=1)
    bidder_id: int = Field(..., example=2)
    amount: Decimal = Field(..., example="1000.00")
    created_at: datetime = Field(...)

    class Config:
        from_attributes = True

class AutoBidCreate(BaseModel):
    auction_id: Optional[int] = Field(None, example=1)
    lot_id: Optional[int] = Field(None, example=1)
    max_amount: Decimal = Field(..., example="5000.00", decimal_places=2)

class AutoBidOut(BaseModel):
    id: int = Field(..., example=1)
    auction_id: Optional[int] = Field(None, example=1)
    lot_id: Optional[int] = Field(None, example=1)
    user_id: int = Field(..., example=2)
    max_amount: Decimal = Field(..., example="5000.00")
    created_at: datetime = Field(...)

    class Config:
        from_attributes = True