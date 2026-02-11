from sqlalchemy import Column, Integer, String, Float, BigInteger, ForeignKey, DateTime, func
from sqlalchemy.orm import relationship
from app.database import Base


class ServerBenchmark(Base):
    __tablename__ = "server_benchmarks"

    id = Column(Integer, primary_key=True, autoincrement=True)
    worker_server_id = Column(Integer, ForeignKey("worker_servers.id", ondelete="CASCADE"), nullable=False)
    upload_mbps = Column(Float, nullable=True)
    download_mbps = Column(Float, nullable=True)
    latency_ms = Column(Float, nullable=True)
    test_file_size_bytes = Column(BigInteger, default=200_000_000)
    status = Column(String(20), default="pending")  # pending, running, completed, failed
    error_message = Column(String(1000), nullable=True)
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, server_default=func.now())

    worker_server = relationship("WorkerServer", back_populates="benchmarks")
