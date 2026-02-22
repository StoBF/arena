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
    modifiers = Column(JSON, default={})  # Наприклад: {"strength": 2, "speed": 1}
    affected = Column(JSON, default=[])   # Наприклад: ["strength", "speed"]

# Для міграції: HeroPerk має отримати perk_id (FK на perks.id) замість perk_name 