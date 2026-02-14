from sqlalchemy import Column, Integer, String, Boolean, DateTime, func
from app.database import Base


class WebhookSource(Base):
    __tablename__ = "webhook_sources"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), nullable=False)
    source_type = Column(String(20), nullable=False)  # "sonarr", "radarr", "custom"
    secret = Column(String(100), nullable=True)
    preset_id = Column(Integer, nullable=True)
    is_enabled = Column(Boolean, default=True)
    last_received_at = Column(DateTime, nullable=True)
    events_received = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
