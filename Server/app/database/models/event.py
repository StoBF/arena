from sqlalchemy import Column, Integer, String, DateTime, JSON, ForeignKey
from sqlalchemy.orm import relationship
from app.database.base import Base
from datetime import datetime

class EventDefinition(Base):
    __tablename__ = "event_definitions"
    id             = Column(Integer, primary_key=True)
    name           = Column(String, unique=True, nullable=False)
    schedule_cron  = Column(String, nullable=False)   # cron expression
    duration_sec   = Column(Integer, nullable=False)  # length of event
    rewards        = Column(JSON, default=list)       # list of {id, type, qty}
    # relationship back to instances
    instances      = relationship("EventInstance", back_populates="definition")

class EventInstance(Base):
    __tablename__ = "event_instances"
    id             = Column(Integer, primary_key=True)
    definition_id  = Column(Integer, ForeignKey("event_definitions.id"), nullable=False)
    start_time     = Column(DateTime, default=datetime.utcnow, nullable=False)
    end_time       = Column(DateTime, nullable=False)
    status         = Column(String, default="upcoming")  # upcoming|active|finished
    participants   = Column(JSON, default=list)           # list of user_ids
    completed_at   = Column(DateTime, nullable=True)

    definition     = relationship("EventDefinition", back_populates="instances") 