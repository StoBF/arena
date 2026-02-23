from sqlalchemy import Column, Integer, ForeignKey, Numeric, String, DateTime, func
from app.database.base import Base


class CurrencyTransaction(Base):
    __tablename__ = "currency_transactions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    amount = Column(Numeric(12, 2), nullable=False)
    type = Column(String(64), nullable=False)
    reference_id = Column(Integer, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
