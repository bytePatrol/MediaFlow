from sqlalchemy import Column, Integer, String, Float, Boolean, JSON, DateTime, func
from sqlalchemy.orm import relationship
from app.database import Base


class WorkerServer(Base):
    __tablename__ = "worker_servers"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), nullable=False)
    hostname = Column(String(255), nullable=False)
    port = Column(Integer, default=22)
    ssh_username = Column(String(100), nullable=True)
    ssh_key_path = Column(String(500), nullable=True)
    role = Column(String(50), default="transcode")
    gpu_model = Column(String(100), nullable=True)
    cpu_model = Column(String(100), nullable=True)
    cpu_cores = Column(Integer, nullable=True)
    ram_gb = Column(Float, nullable=True)
    hw_accel_types = Column(JSON, nullable=True)
    max_concurrent_jobs = Column(Integer, default=1)
    status = Column(String(20), default="offline", index=True)
    last_heartbeat_at = Column(DateTime, nullable=True)
    hourly_cost = Column(Float, nullable=True)
    is_local = Column(Boolean, default=False)
    is_enabled = Column(Boolean, default=True)
    working_directory = Column(String(500), default="/tmp/mediaflow")
    path_mappings = Column(JSON, nullable=True, default=[])
    # Format: [{"source_prefix": "/share/ZFS18_DATA/", "target_prefix": "/Volumes/MediaNAS/"}]
    performance_score = Column(Float, nullable=True)  # 0-100, from benchmarks
    last_benchmark_at = Column(DateTime, nullable=True)
    consecutive_failures = Column(Integer, default=0)
    provision_log = Column(String, nullable=True)  # JSON result of last provisioning
    # Cloud GPU fields
    cloud_provider = Column(String(20), nullable=True)       # "vultr" or None for manual servers
    cloud_instance_id = Column(String(100), nullable=True)   # Vultr instance UUID
    cloud_plan = Column(String(50), nullable=True)           # e.g. "vcg-a16-6c-64g-16vram"
    cloud_region = Column(String(20), nullable=True)         # e.g. "ewr", "lax"
    cloud_created_at = Column(DateTime, nullable=True)       # When instance was created (for billing)
    cloud_auto_teardown = Column(Boolean, default=True)      # Whether to auto-destroy on idle
    cloud_idle_minutes = Column(Integer, default=30)         # Minutes of idle before teardown
    cloud_status = Column(String(20), nullable=True)         # "creating", "bootstrapping", "active", "destroying"
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    transcode_jobs = relationship("TranscodeJob", back_populates="worker_server")
    job_logs = relationship("JobLog", back_populates="worker_server")
    benchmarks = relationship("ServerBenchmark", back_populates="worker_server", cascade="all, delete-orphan")
