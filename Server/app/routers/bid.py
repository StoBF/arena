# app/routers/bid.py

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.schemas.bid import BidCreate, BidOut
from app.schemas.pagination import BidsPaginatedResponse
from app.services.bid import BidService
from app.database.session import get_session
from app.auth import get_current_user_info

router = APIRouter(prefix="/bids", tags=["Bids"])


@router.post(
    "/",
    response_model=BidOut,
    summary="Place a new bid (item or hero)",
    description="Places a new bid on a specified auction (item) or auction lot (hero). Only authenticated users can place bids. Supports idempotent requests via request_id UUID field."
)
async def place_bid(data: BidCreate, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    service = BidService(db)
    user_id = current_user["user_id"]
    if hasattr(data, 'lot_id') and data.lot_id is not None:
        bid = await service.place_lot_bid(bidder_id=user_id, lot_id=data.lot_id, amount=data.amount, request_id=data.request_id)
    else:
        bid = await service.place_bid(bidder_id=user_id, auction_id=data.auction_id, amount=data.amount, request_id=data.request_id)
    return BidOut.from_orm(bid)


@router.get(
    "/",
    response_model=BidsPaginatedResponse,
    summary="List all bids",
    description="Returns a paginated list of all bids placed by the authenticated user."
)
async def read_bids(
    limit: int = Query(10, ge=1, le=100, description="Items per page (max 100)"),
    offset: int = Query(0, ge=0, description="Items to skip"),
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    service = BidService(db)
    result = await service.list_bids(limit=limit, offset=offset)
    
    return {
        "items": [BidOut.from_orm(b) for b in result["items"]],
        "total": result["total"],
        "limit": result["limit"],
        "offset": result["offset"]
    }


@router.get(
    "/{bid_id}",
    response_model=BidOut,
    summary="Get bid by ID",
    description="Returns detailed information about a specific bid by its ID."
)
async def read_bid(bid_id: int, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    service = BidService(db)
    bid = await service.get_bid(bid_id)
    if not bid:
        raise HTTPException(404, "Bid not found")
    return BidOut.from_orm(bid)


@router.delete(
    "/{bid_id}",
    response_model=BidOut,
    summary="Delete a bid",
    description="Deletes a bid by its ID. Only the owner or an admin can delete bids."
)
async def delete_bid(bid_id: int, db: AsyncSession = Depends(get_session), current_user = Depends(get_current_user_info)):
    service = BidService(db)
    deleted = await service.delete_bid(bid_id)
    if not deleted:
        raise HTTPException(404, "Bid not found")
    return BidOut.from_orm(deleted)
