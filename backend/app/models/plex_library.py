from sqlalchemy import Column, Integer, String, BigInteger, ForeignKey, DateTime, func
from sqlalchemy.orm import relationship
from app.database import Base


class PlexLibrary(Base):
    __tablename__ = "plex_libraries"

    id = Column(Integer, primary_key=True, autoincrement=True)
    plex_server_id = Column(Integer, ForeignKey("plex_servers.id", ondelete="CASCADE"), nullable=False)
    plex_key = Column(String(50), nullable=False)
    title = Column(String(255), nullable=False)
    type = Column(String(50), nullable=False)
    total_items = Column(Integer, default=0)
    total_size = Column(BigInteger, default=0)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    server = relationship("PlexServer", back_populates="libraries")
    media_items = relationship("MediaItem", back_populates="library", cascade="all, delete-orphan")
