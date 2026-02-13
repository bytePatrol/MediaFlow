from sqlalchemy import Column, Integer, String, Float, BigInteger, Boolean, ForeignKey, DateTime, func
from sqlalchemy.orm import relationship
from app.database import Base


class AnalysisRun(Base):
    __tablename__ = "analysis_runs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    started_at = Column(DateTime, server_default=func.now())
    completed_at = Column(DateTime, nullable=True)
    total_items_analyzed = Column(Integer, default=0)
    recommendations_generated = Column(Integer, default=0)
    total_estimated_savings = Column(BigInteger, default=0)
    trigger = Column(String(20), default="manual")  # manual, auto, scheduled

    recommendations = relationship("Recommendation", back_populates="analysis_run")


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
    priority_score = Column(Float, nullable=True)
    confidence = Column(Float, nullable=True)
    analysis_run_id = Column(Integer, ForeignKey("analysis_runs.id", ondelete="SET NULL"), nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    media_item = relationship("MediaItem", back_populates="recommendations")
    analysis_run = relationship("AnalysisRun", back_populates="recommendations")
