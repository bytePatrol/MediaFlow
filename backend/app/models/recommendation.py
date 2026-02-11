from sqlalchemy import Column, Integer, String, Float, BigInteger, Boolean, ForeignKey, DateTime, func
from sqlalchemy.orm import relationship
from app.database import Base


class Recommendation(Base):
    __tablename__ = "recommendations"

    id = Column(Integer, primary_key=True, autoincrement=True)
    media_item_id = Column(Integer, ForeignKey("media_items.id", ondelete="CASCADE"), nullable=True)
    type = Column(String(50), nullable=False, index=True)
    severity = Column(String(20), default="info")
    title = Column(String(500), nullable=False)
    description = Column(String(2000), nullable=True)
    estimated_savings = Column(BigInteger, nullable=True)
    suggested_preset_id = Column(Integer, ForeignKey("transcode_presets.id", ondelete="SET NULL"), nullable=True)
    is_dismissed = Column(Boolean, default=False)
    is_actioned = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())

    media_item = relationship("MediaItem", back_populates="recommendations")
