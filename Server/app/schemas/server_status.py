from pydantic import BaseModel


class ServerStatusOut(BaseModel):
    status: str
    online_players: int
