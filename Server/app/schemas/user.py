from pydantic import BaseModel, EmailStr, Field
from typing import Optional
from decimal import Decimal

class UserCreate(BaseModel):
    email: EmailStr = Field(..., example="user@example.com")
    username: Optional[str] = Field(None, min_length=3, max_length=32, example="username")
    password: Optional[str] = Field(None, min_length=6, max_length=128, example="strongpassword")

class UserLogin(BaseModel):
    login: str = Field(..., min_length=3, max_length=128, example="user@example.com або username")
    password: Optional[str] = Field(None, min_length=6, max_length=128, example="strongpassword")

class UserOut(BaseModel):
    id: int = Field(..., example=1)
    email: EmailStr = Field(..., example="user@example.com")
    username: Optional[str] = Field(None, example="username")

    class Config:
        from_attributes = True

class UserWithBalance(BaseModel):
    id: int = Field(..., example=1)
    email: EmailStr = Field(..., example="user@example.com")
    username: Optional[str] = Field(None, example="username")
    balance: Decimal = Field(..., example="1500.00", decimal_places=2)
    reserved: Decimal = Field(..., example="500.00", decimal_places=2)

    class Config:
        from_attributes = True

class TokenResponse(BaseModel):
    access_token: str = Field(..., example="eyJhbGciOiJIUzI1NiIsInR5cCI6...")
    refresh_token: str = Field(..., example="eyJhbGciOiJIUzI1NiIsInR5cCI6...")
    token_type: str = Field(..., example="bearer")

class TokenRefreshResponse(BaseModel):
    access_token: str = Field(..., example="eyJhbGciOiJIUzI1NiIsInR5cCI6...")
    token_type: str = Field(..., example="bearer")
