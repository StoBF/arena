# Модель для майбутнього довідника перків (поки не використовується у продакшн)
from sqlalchemy import Column, Integer, String, JSON
from app.database.base import Base

class Perk(Base):
    __tablename__ = "perks"
    id = Column(Integer, primary_key=True)
    name = Column(String(50), unique=True, nullable=False)
    description = Column(String(255), nullable=True)
    effect_type = Column(String(30), nullable=True)  # offensive/defensive/support/utility
    max_level = Column(Integer, default=100)
    modifiers = Column(JSON, default={})  # v2 stat keys, e.g. {"stamina": 2, "reflex": 1}
    affected = Column(JSON, default=[])   # v2 stat keys, e.g. ["stamina", "reflex"]