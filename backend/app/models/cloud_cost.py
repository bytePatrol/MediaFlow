from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey, func
from app.database import Base


class CloudCostRecord(Base):
    __tablename__ = "cloud_cost_records"

    id = Column(Integer, primary_key=True, autoincrement=True)
    worker_server_id = Column(Integer, ForeignKey("worker_servers.id", ondelete="SET NULL"), nullable=True)
    job_id = Column(Integer, ForeignKey("transcode_jobs.id", ondelete="SET NULL"), nullable=True)
    cloud_provider = Column(String(20))          # "vultr"
    cloud_instance_id = Column(String(100))
    cloud_plan = Column(String(50))
    hourly_rate = Column(Float)
    start_time = Column(DateTime)                # Job start or instance create time
    end_time = Column(DateTime, nullable=True)   # Job end or instance destroy time
    duration_seconds = Column(Float, nullable=True)
    cost_usd = Column(Float, nullable=True)      # Computed: duration_hours * hourly_rate
    record_type = Column(String(20))             # "job" or "instance"
    created_at = Column(DateTime, server_default=func.now())
