from sqlalchemy import Column, Integer, String, BigInteger, Float, Boolean, ForeignKey, DateTime, Index, JSON, func
from sqlalchemy.orm import relationship
from app.database import Base


class MediaItem(Base):
    __tablename__ = "media_items"

    id = Column(Integer, primary_key=True, autoincrement=True)
    plex_library_id = Column(Integer, ForeignKey("plex_libraries.id", ondelete="CASCADE"), nullable=False)
    plex_rating_key = Column(String(50), nullable=False)
    title = Column(String(500), nullable=False)
    year = Column(Integer, nullable=True)
    duration_ms = Column(BigInteger, nullable=True)
    thumb_url = Column(String(1000), nullable=True)
    file_path = Column(String(2000), nullable=True)
    file_size = Column(BigInteger, nullable=True)
    container = Column(String(20), nullable=True)
    video_codec = Column(String(50), nullable=True)
    video_profile = Column(String(50), nullable=True)
    video_bitrate = Column(BigInteger, nullable=True)
    width = Column(Integer, nullable=True)
    height = Column(Integer, nullable=True)
    resolution_tier = Column(String(20), nullable=True)
    frame_rate = Column(Float, nullable=True)
    is_hdr = Column(Boolean, default=False)
    hdr_format = Column(String(50), nullable=True)
    bit_depth = Column(Integer, nullable=True)
    audio_codec = Column(String(50), nullable=True)
    audio_channels = Column(Integer, nullable=True)
    audio_channel_layout = Column(String(50), nullable=True)
    audio_bitrate = Column(BigInteger, nullable=True)
    audio_tracks_json = Column(JSON, nullable=True)
    subtitle_tracks_json = Column(JSON, nullable=True)
    play_count = Column(Integer, default=0)
    genres = Column(JSON, nullable=True)
    directors = Column(JSON, nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())

    library = relationship("PlexLibrary", back_populates="media_items")
    transcode_jobs = relationship("TranscodeJob", back_populates="media_item")
    recommendations = relationship("Recommendation", back_populates="media_item")
    tags = relationship("MediaTag", back_populates="media_item", cascade="all, delete-orphan")

    __table_args__ = (
        Index("idx_media_library", "plex_library_id"),
        Index("idx_media_resolution", "resolution_tier"),
        Index("idx_media_codec", "video_codec"),
        Index("idx_media_size", "file_size"),
        Index("idx_media_title", "title"),
        Index("idx_media_rating_key", "plex_rating_key"),
    )
