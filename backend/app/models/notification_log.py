from sqlalchemy import Column, Integer, String, Text, DateTime, func
from app.database import Base


class NotificationLog(Base):
    __tablename__ = "notification_logs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    event = Column(String(100), nullable=False)
    channel_type = Column(String(20), nullable=False)
    channel_name = Column(String(100), nullable=True)
    payload_json = Column(Text, nullable=True)
    status = Column(String(20), nullable=False, default="sent")
    error_message = Column(Text, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
