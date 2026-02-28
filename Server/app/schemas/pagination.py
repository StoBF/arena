"""Pagination schemas for list endpoints."""

from pydantic import BaseModel, Field, ConfigDict
from typing import Generic, TypeVar, List

T = TypeVar('T')


class PaginationParams(BaseModel):
    """Pagination request parameters."""
    limit: int = Field(10, ge=1, le=100, description="Number of items to return (max 100)")
    offset: int = Field(0, ge=0, description="Number of items to skip")


class PaginatedResponse(BaseModel, Generic[T]):
    model_config = ConfigDict(arbitrary_types_allowed=True)

    """Generic paginated response schema.
    
    Usage:
        class HeroResponse(PaginatedResponse[HeroRead]):
            pass
    """
    items: List[T] = Field(..., description="List of items")
    total: int = Field(..., description="Total number of items available")
    limit: int = Field(..., description="Items per page")
    offset: int = Field(..., description="Number of items skipped")
    

# Concrete paginated response schemas for each endpoint

class HeroesPaginatedResponse(BaseModel):
    """Paginated response for heroes list."""
    items: List = Field(..., description="List of heroes")
    total: int = Field(..., description="Total number of heroes")
    limit: int = Field(..., description="Heroes per page")
    offset: int = Field(..., description="Number of heroes skipped")


class AuctionsPaginatedResponse(BaseModel):
    """Paginated response for auctions list."""
    items: List = Field(..., description="List of auctions")
    total: int = Field(..., description="Total number of auctions")
    limit: int = Field(..., description="Auctions per page")
    offset: int = Field(..., description="Number of auctions skipped")


class AuctionLotsPaginatedResponse(BaseModel):
    """Paginated response for auction lots list."""
    items: List = Field(..., description="List of auction lots")
    total: int = Field(..., description="Total number of auction lots")
    limit: int = Field(..., description="Lots per page")
    offset: int = Field(..., description="Number of lots skipped")


class BidsPaginatedResponse(BaseModel):
    """Paginated response for bids list."""
    items: List = Field(..., description="List of bids")
    total: int = Field(..., description="Total number of bids")
    limit: int = Field(..., description="Bids per page")
    offset: int = Field(..., description="Number of bids skipped")


def get_pagination_params(limit: int = 10, offset: int = 0) -> dict:
    """Validate and return pagination parameters.
    
    Args:
        limit: Items per page (max 100)
        offset: Items to skip
        
    Returns:
        dict with validated limit and offset
        
    Raises:
        ValueError if limit > 100
    """
    # Enforce maximum limit
    if limit > 100:
        limit = 100
    if limit < 1:
        limit = 1
    if offset < 0:
        offset = 0
    
    return {"limit": limit, "offset": offset}
