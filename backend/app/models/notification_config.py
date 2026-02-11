from sqlalchemy import Column, Integer, String, Boolean, JSON, DateTime, func
from app.database import Base


class NotificationConfig(Base):
    __tablename__ = "notification_configs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    type = Column(String(20), nullable=False)
    name = Column(String(100), nullable=False)
    config_json = Column(JSON, nullable=True)
    events = Column(JSON, nullable=True)
    is_enabled = Column(Boolean, default=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
