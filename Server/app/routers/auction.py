from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List
from app.schemas.auction import AuctionCreate, AuctionOut, AuctionLotCreate, AuctionLotOut, AutoBidCreate, AutoBidOut
from app.schemas.pagination import AuctionsPaginatedResponse, AuctionLotsPaginatedResponse
from app.services.auction import AuctionService
from app.services.auction_lot import AuctionLotService
from app.services.bid import BidService
from app.database.session import get_session
from app.auth import get_current_user_info
from app.core.redis_cache import redis_cache

router = APIRouter(prefix="/auctions", tags=["Auction"])

@router.post(
    "/",
    response_model=AuctionOut,
    summary="Create a new auction",
    description="Creates a new auction for the authenticated user with the specified item, start price, duration, and quantity."
)
async def create_auction(data: AuctionCreate, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    service = AuctionService(db)
    auction = await service.create_auction(seller_id=current_user["user_id"], item_id=data.item_id, start_price=data.start_price, duration=data.duration, quantity=data.quantity)
    return AuctionOut.model_validate(auction, from_attributes=True)

@router.get(
    "/",
    response_model=AuctionsPaginatedResponse,
    summary="List all active auctions",
    description="Returns a paginated list of all currently active auctions. Uses Redis cache for performance."
)
async def list_auctions(
    limit: int = Query(10, ge=1, le=100, description="Items per page (max 100)"),
    offset: int = Query(0, ge=0, description="Items to skip"),
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    cache_key = f"auctions:active:{limit}:{offset}"
    cached = await redis_cache.get(cache_key)
    if cached is not None:
        return cached

    service = AuctionService(db)
    result = await service.list_auctions(active_only=True, limit=limit, offset=offset)

    items = [AuctionOut.model_validate(a, from_attributes=True) for a in result["items"]]
    response = {
        "items": items,
        "total": result["total"],
        "limit": result["limit"],
        "offset": result["offset"],
    }
    await redis_cache.set(
        cache_key,
        {
            "items": [a.model_dump() for a in items],
            "total": response["total"],
            "limit": response["limit"],
            "offset": response["offset"],
        },
        expire=30,
    )
    return response

@router.post(
    "/{auction_id}/cancel",
    response_model=AuctionOut,
    summary="Cancel an auction",
    description="Cancels an auction if the authenticated user is the seller."
)
async def cancel_auction(auction_id: int, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    service = AuctionService(db)
    auction = await service.cancel_auction(auction_id, seller_id=current_user["user_id"])
    return AuctionOut.model_validate(auction, from_attributes=True)

@router.post(
    "/{auction_id}/close",
    response_model=AuctionOut,
    summary="Close an auction",
    description="Closes an auction and determines the winner."
)
async def close_auction(auction_id: int, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    service = AuctionService(db)
    auction = await service.get_auction(auction_id)
    if not auction:
        raise HTTPException(404, "Auction not found")
    if auction.seller_id != current_user["user_id"] and current_user.get("role") != "admin":
        raise HTTPException(403, "Only the seller or an admin can close this auction")
    auction = await service.close_auction(auction_id)
    return AuctionOut.model_validate(auction, from_attributes=True)

@router.post(
    "/lots",
    response_model=AuctionLotOut,
    summary="Create a new hero auction lot",
    description="Creates a new auction lot for a hero."
)
async def create_auction_lot(data: AuctionLotCreate, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    service = AuctionLotService(db)
    lot = await service.create_auction_lot(hero_id=data.hero_id, seller_id=current_user["user_id"], starting_price=data.starting_price, duration=data.duration, buyout_price=data.buyout_price)
    return AuctionLotOut.model_validate(lot, from_attributes=True)

@router.get(
    "/lots",
    response_model=AuctionLotsPaginatedResponse,
    summary="List all active hero auction lots",
    description="Returns a paginated list of all currently active hero auction lots."
)
async def list_auction_lots(
    limit: int = Query(10, ge=1, le=100, description="Items per page (max 100)"),
    offset: int = Query(0, ge=0, description="Items to skip"),
    db: AsyncSession = Depends(get_session),
    current_user=Depends(get_current_user_info)
):
    cache_key = f"auctions:active_lots:{limit}:{offset}"
    cached = await redis_cache.get(cache_key)
    if cached is not None:
        return cached

    service = AuctionLotService(db)
    result = await service.list_auction_lots(limit=limit, offset=offset)

    items = [AuctionLotOut.model_validate(l, from_attributes=True) for l in result["items"]]
    response = {
        "items": items,
        "total": result["total"],
        "limit": result["limit"],
        "offset": result["offset"],
    }
    await redis_cache.set(
        cache_key,
        {
            "items": [l.model_dump() for l in items],
            "total": response["total"],
            "limit": response["limit"],
            "offset": response["offset"],
        },
        expire=30,
    )
    return response

@router.get(
    "/{auction_id}",
    response_model=AuctionOut,
    summary="Get auction by ID",
    description="Returns detailed information about a specific auction by its ID."
)
async def get_auction(auction_id: int, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    service = AuctionService(db)
    auction = await service.get_auction(auction_id)
    if not auction:
        raise HTTPException(404, "Auction not found")
    return AuctionOut.model_validate(auction, from_attributes=True)

@router.post(
    "/lots/{lot_id}/close",
    response_model=AuctionLotOut,
    summary="Close a hero auction lot",
    description="Closes a hero auction lot and determines the winner."
)
async def close_auction_lot(lot_id: int, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    service = AuctionLotService(db)
    lot = await service.get_auction_lot(lot_id)
    if not lot:
        raise HTTPException(404, "Auction lot not found")
    if lot.seller_id != current_user["user_id"] and current_user.get("role") != "admin":
        raise HTTPException(403, "Only the seller or an admin can close this lot")
    lot = await service.close_auction_lot(lot_id)
    return AuctionLotOut.model_validate(lot, from_attributes=True)

@router.post(
    "/lots/{lot_id}/buyout",
    response_model=AuctionLotOut,
    summary="Buy out a hero auction lot immediately",
    description="Immediately purchases a hero auction lot at the buyout price."
)
async def buyout_auction_lot(lot_id: int, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    service = AuctionLotService(db)
    lot = await service.get_auction_lot(lot_id)
    if not lot:
        raise HTTPException(404, "Auction lot not found")
    if lot.buyout_price is None:
        raise HTTPException(400, "This lot has no buyout price set")
    lot = await service.close_auction_lot(lot_id, winner_id=current_user["user_id"])
    return AuctionLotOut.model_validate(lot, from_attributes=True)

@router.post(
    "/lots/{lot_id}/delete",
    response_model=AuctionLotOut,
    summary="Delete a hero auction lot",
    description="Deletes a hero auction lot if no bids have been placed."
)
async def delete_auction_lot(lot_id: int, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    service = AuctionLotService(db)
    lot = await service.delete_auction_lot(lot_id, seller_id=current_user["user_id"])
    return AuctionLotOut.model_validate(lot, from_attributes=True)

@router.post(
    "/autobid",
    response_model=AutoBidOut,
    summary="Set an autobid for an auction or lot",
    description="Sets or updates an autobid for the authenticated user."
)
async def set_autobid(data: AutoBidCreate, db: AsyncSession = Depends(get_session), current_user=Depends(get_current_user_info)):
    service = BidService(db)
    autobid = await service.set_auto_bid(user_id=current_user["user_id"], auction_id=data.auction_id, lot_id=data.lot_id, max_amount=data.max_amount)
    return AutoBidOut.model_validate(autobid, from_attributes=True)
