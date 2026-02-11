from sqlalchemy import Column, Integer, String, Boolean, Float, JSON, DateTime, func
from app.database import Base


class TranscodePreset(Base):
    __tablename__ = "transcode_presets"

    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), nullable=False)
    description = Column(String(500), nullable=True)
    is_builtin = Column(Boolean, default=False)
    video_codec = Column(String(50), default="libx265")
    target_resolution = Column(String(20), nullable=True)
    bitrate_mode = Column(String(10), default="crf")
    crf_value = Column(Integer, nullable=True, default=23)
    target_bitrate = Column(String(20), nullable=True)
    hw_accel = Column(String(50), nullable=True)
    audio_mode = Column(String(20), default="copy")
    audio_codec = Column(String(50), nullable=True)
    container = Column(String(10), default="mkv")
    subtitle_mode = Column(String(20), default="copy")
    custom_flags = Column(String(1000), nullable=True)
    hdr_mode = Column(String(20), default="preserve")
    two_pass = Column(Boolean, default=False)
    encoder_tune = Column(String(50), nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
