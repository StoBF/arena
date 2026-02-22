from sqlalchemy import Column, Integer, String, DateTime, JSON, ForeignKey
from sqlalchemy.orm import relationship
from app.database.base import Base
from datetime import datetime

class TournamentTemplate(Base):
    __tablename__ = "tournament_templates"
    id               = Column(Integer, primary_key=True)
    name             = Column(String, unique=True, nullable=False)
    format           = Column(String, nullable=False)   # e.g. "single_elimination", "double_elimination"
    min_rank         = Column(Integer, default=0)
    max_rank         = Column(Integer, default=100000)
    max_participants = Column(Integer, nullable=False)
    instances        = relationship("TournamentInstance", back_populates="template")

class TournamentInstance(Base):
    __tablename__ = "tournament_instances"
    id             = Column(Integer, primary_key=True)
    template_id    = Column(Integer, ForeignKey("tournament_templates.id"), nullable=False)
    participants   = Column(JSON, default=list)         # list of user IDs
    bracket        = Column(JSON, default=dict)         # nested rounds & matches
    status         = Column(String, default="pending") # pending|active|completed
    created_at     = Column(DateTime, default=datetime.utcnow)
    completed_at   = Column(DateTime, nullable=True)

    template = relationship("TournamentTemplate", back_populates="instances") 