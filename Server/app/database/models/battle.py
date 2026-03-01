from datetime import datetime

from sqlalchemy import CheckConstraint, Column, DateTime, ForeignKey, Integer, Numeric, UniqueConstraint
from sqlalchemy.orm import relationship

from app.database.base import Base


class BattleQueueEntry(Base):
    __tablename__ = "battle_queue"

    id = Column(Integer, primary_key=True, index=True)
    hero_id = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    player_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True, index=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    hero = relationship("app.database.models.hero.Hero")
    player = relationship("User")


class BattleBet(Base):
    __tablename__ = "battle_bets"

    id = Column(Integer, primary_key=True, index=True)
    bettor_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    hero_id = Column(Integer, ForeignKey("heroes.id", ondelete="CASCADE"), nullable=False, index=True)
    amount = Column(Numeric(12, 2), nullable=False)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)

    bettor = relationship("User")
    hero = relationship("app.database.models.hero.Hero")

    __table_args__ = (
        UniqueConstraint("bettor_id", "hero_id", name="uq_battle_bet_bettor_hero"),
        CheckConstraint("amount > 0", name="ck_battle_bet_amount_positive"),
    )
