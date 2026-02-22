from pydantic import BaseModel, Field

class StashCreate(BaseModel):
    item_id: int = Field(..., example=101)
    quantity: int = Field(1, example=1)

class StashOut(BaseModel):
    id: int = Field(..., example=1)
    user_id: int = Field(..., example=5)
    item_id: int = Field(..., example=101)
    quantity: int = Field(..., example=1)

    class Config:
        from_attributes = True
