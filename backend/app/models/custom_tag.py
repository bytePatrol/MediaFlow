from sqlalchemy import Column, Integer, String, ForeignKey, DateTime, func
from sqlalchemy.orm import relationship
from app.database import Base


class CustomTag(Base):
    __tablename__ = "custom_tags"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), nullable=False, unique=True)
    color = Column(String(7), default="#256af4")
    created_at = Column(DateTime, server_default=func.now())

    media_tags = relationship("MediaTag", back_populates="tag", cascade="all, delete-orphan")


class MediaTag(Base):
    __tablename__ = "media_tags"

    id = Column(Integer, primary_key=True, autoincrement=True)
    media_item_id = Column(Integer, ForeignKey("media_items.id", ondelete="CASCADE"), nullable=False)
    tag_id = Column(Integer, ForeignKey("custom_tags.id", ondelete="CASCADE"), nullable=False)
    created_at = Column(DateTime, server_default=func.now())

    media_item = relationship("MediaItem", back_populates="tags")
    tag = relationship("CustomTag", back_populates="media_tags")
