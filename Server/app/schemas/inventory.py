from pydantic import BaseModel, Field, ConfigDict

class StashCreate(BaseModel):
    item_id: int = Field(...)
    quantity: int = Field(1)

class StashOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int = Field(...)
    user_id: int = Field(...)
    item_id: int = Field(...)
    quantity: int = Field(...)
