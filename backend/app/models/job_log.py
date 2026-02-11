from sqlalchemy import Column, Integer, String, Float, BigInteger, ForeignKey, DateTime, func
from sqlalchemy.orm import relationship
from app.database import Base


class JobLog(Base):
    __tablename__ = "job_logs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    job_id = Column(Integer, ForeignKey("transcode_jobs.id", ondelete="CASCADE"), nullable=False)
    worker_server_id = Column(Integer, ForeignKey("worker_servers.id", ondelete="SET NULL"), nullable=True)
    media_item_id = Column(Integer, ForeignKey("media_items.id", ondelete="SET NULL"), nullable=True)
    title = Column(String(500), nullable=True)
    source_codec = Column(String(50), nullable=True)
    source_resolution = Column(String(20), nullable=True)
    source_size = Column(BigInteger, nullable=True)
    target_codec = Column(String(50), nullable=True)
    target_resolution = Column(String(20), nullable=True)
    target_size = Column(BigInteger, nullable=True)
    size_reduction = Column(Float, nullable=True)
    duration_seconds = Column(Float, nullable=True)
    avg_fps = Column(Float, nullable=True)
    status = Column(String(20), nullable=False)
    compute_cost = Column(Float, nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    job = relationship("TranscodeJob", back_populates="job_logs")
    worker_server = relationship("WorkerServer", back_populates="job_logs")
