# app/database/models/user.py

from sqlalchemy import Column, Integer, String, Boolean, Numeric, CheckConstraint
from sqlalchemy.orm import relationship
from app.database.base import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String, unique=True, index=True, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    hashed_password = Column(String, nullable=True)
    is_active = Column(Boolean, default=True)
    is_google_account = Column(Boolean, default=False)
    balance = Column(Numeric(12, 2), default=0, nullable=False)  # User's available balance
    reserved = Column(Numeric(12, 2), default=0, nullable=False)  # Funds reserved for bids
    role = Column(String, default="user", nullable=False)  # user, admin, moderator
    __table_args__ = (
        CheckConstraint('balance >= 0', name='ck_user_balance_non_negative'),
        CheckConstraint('reserved >= 0', name='ck_user_reserved_non_negative'),
    )

    heroes = relationship("app.database.models.hero.Hero", back_populates="owner")
    items = relationship("Stash", back_populates="owner")
