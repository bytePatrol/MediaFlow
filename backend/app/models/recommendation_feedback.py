from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, func
from app.database import Base


class RecommendationFeedback(Base):
    __tablename__ = "recommendation_feedback"

    id = Column(Integer, primary_key=True, autoincrement=True)
    recommendation_id = Column(Integer, ForeignKey("recommendations.id", ondelete="CASCADE"), nullable=False)
    media_item_id = Column(Integer, ForeignKey("media_items.id", ondelete="SET NULL"), nullable=True)
    action = Column(String(20), nullable=False)  # "dismissed", "queued", "completed"
    dismiss_reason = Column(String(50), nullable=True)  # "keep_4k", "keep_codec", "too_important", "other"
    estimated_savings = Column(Float, nullable=True)
    actual_savings = Column(Float, nullable=True)  # filled in after transcode completes
    source_codec = Column(String(50), nullable=True)
    target_codec = Column(String(50), nullable=True)
    resolution = Column(String(20), nullable=True)
    created_at = Column(DateTime, server_default=func.now())
