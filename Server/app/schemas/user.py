from pydantic import BaseModel, EmailStr, Field, ConfigDict
from typing import Optional
from decimal import Decimal

class UserCreate(BaseModel):
    email: EmailStr = Field(...)
    username: str = Field(..., min_length=3, max_length=32)
    password: Optional[str] = Field(None, min_length=6, max_length=128)

class UserLogin(BaseModel):
    login: str = Field(..., min_length=3, max_length=128)
    password: Optional[str] = Field(None, min_length=6, max_length=128)

class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    email: EmailStr = Field(...)
    username: Optional[str] = Field(None)

class UserWithBalance(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    email: EmailStr = Field(...)
    username: Optional[str] = Field(None)
    balance: Decimal = Field(..., decimal_places=2)
    reserved: Decimal = Field(..., decimal_places=2)

class TokenResponse(BaseModel):
    access_token: str = Field(...)
    refresh_token: str = Field(...)
    token_type: str = Field(...)

class TokenRefreshResponse(BaseModel):
    access_token: str = Field(...)
    token_type: str = Field(...)
