from sqlalchemy import Column, Integer, String, Float, BigInteger, Boolean, ForeignKey, DateTime, JSON, func
from sqlalchemy.orm import relationship
from app.database import Base


class TranscodeJob(Base):
    __tablename__ = "transcode_jobs"

    id = Column(Integer, primary_key=True, autoincrement=True)
    media_item_id = Column(Integer, ForeignKey("media_items.id", ondelete="SET NULL"), nullable=True)
    preset_id = Column(Integer, ForeignKey("transcode_presets.id", ondelete="SET NULL"), nullable=True)
    worker_server_id = Column(Integer, ForeignKey("worker_servers.id", ondelete="SET NULL"), nullable=True)
    config_json = Column(JSON, nullable=True)
    status = Column(String(20), default="queued", index=True)
    priority = Column(Integer, default=0)
    progress_percent = Column(Float, default=0.0)
    current_fps = Column(Float, nullable=True)
    eta_seconds = Column(Integer, nullable=True)
    source_path = Column(String(2000), nullable=True)
    source_size = Column(BigInteger, nullable=True)
    output_path = Column(String(2000), nullable=True)
    output_size = Column(BigInteger, nullable=True)
    transfer_mode = Column(String(20), nullable=True)       # "local", "mapped", "ssh_transfer"
    worker_input_path = Column(String(2000), nullable=True)  # Resolved path on the worker
    worker_output_path = Column(String(2000), nullable=True)
    ffmpeg_command = Column(String(5000), nullable=True)
    ffmpeg_log = Column(String, nullable=True)
    checkpoint_frame = Column(Integer, nullable=True)
    scheduled_after = Column(DateTime, nullable=True)
    is_dry_run = Column(Boolean, default=False)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)

    media_item = relationship("MediaItem", back_populates="transcode_jobs")
    worker_server = relationship("WorkerServer", back_populates="transcode_jobs")
    job_logs = relationship("JobLog", back_populates="job", cascade="all, delete-orphan")
