from sqlalchemy import Column, Integer, String, Boolean, DateTime, Float, func
from app.database import Base


class WatchFolder(Base):
    __tablename__ = "watch_folders"

    id = Column(Integer, primary_key=True, autoincrement=True)
    path = Column(String(2000), nullable=False)
    preset_id = Column(Integer, nullable=True)
    extensions = Column(String(500), default="mkv,mp4,avi,mov,ts,m4v,wmv")
    delay_seconds = Column(Integer, default=30)
    is_enabled = Column(Boolean, default=True)
    last_scan_at = Column(DateTime, nullable=True)
    files_processed = Column(Integer, default=0)
    created_at = Column(DateTime, server_default=func.now())
