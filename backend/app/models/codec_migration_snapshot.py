from sqlalchemy import Column, Integer, String, BigInteger, Float, DateTime, ForeignKey, func
from app.database import Base


class CodecMigrationSnapshot(Base):
    __tablename__ = "codec_migration_snapshots"

    id = Column(Integer, primary_key=True, autoincrement=True)
    library_id = Column(Integer, ForeignKey("plex_libraries.id", ondelete="CASCADE"), nullable=True)  # null = global
    snapshot_date = Column(DateTime, server_default=func.now())
    codec_distribution_json = Column(String, nullable=True)  # JSON: {"hevc": 450, "h264": 200, ...}
    total_items = Column(Integer, default=0)
    total_size = Column(BigInteger, default=0)
    modern_codec_pct = Column(Float, default=0.0)
    created_at = Column(DateTime, server_default=func.now())
