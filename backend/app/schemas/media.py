from pydantic import BaseModel
from typing import Optional, List, Any
from datetime import datetime

from app.schemas.tag import TagBrief


class MediaItemResponse(BaseModel):
    id: int
    plex_library_id: int
    plex_rating_key: str
    title: str
    year: Optional[int] = None
    duration_ms: Optional[int] = None
    thumb_url: Optional[str] = None
    file_path: Optional[str] = None
    file_size: Optional[int] = None
    container: Optional[str] = None
    video_codec: Optional[str] = None
    video_profile: Optional[str] = None
    video_bitrate: Optional[int] = None
    width: Optional[int] = None
    height: Optional[int] = None
    resolution_tier: Optional[str] = None
    frame_rate: Optional[float] = None
    is_hdr: bool = False
    hdr_format: Optional[str] = None
    bit_depth: Optional[int] = None
    audio_codec: Optional[str] = None
    audio_channels: Optional[int] = None
    audio_channel_layout: Optional[str] = None
    audio_bitrate: Optional[int] = None
    audio_tracks_json: Optional[Any] = None
    subtitle_tracks_json: Optional[Any] = None
    play_count: int = 0
    genres: Optional[List[str]] = None
    directors: Optional[List[str]] = None
    library_title: Optional[str] = None
    tags: Optional[List[TagBrief]] = None

    model_config = {"from_attributes": True}


class MediaItemBrief(BaseModel):
    id: int
    title: str
    year: Optional[int] = None
    resolution_tier: Optional[str] = None
    video_codec: Optional[str] = None
    file_size: Optional[int] = None

    model_config = {"from_attributes": True}


class LibraryStatsResponse(BaseModel):
    total_items: int
    total_size: int
    total_duration_ms: int
    codec_breakdown: dict
    resolution_breakdown: dict
    hdr_count: int
    avg_bitrate: float
    libraries: List[dict]


class LibrarySectionResponse(BaseModel):
    id: int
    title: str
    type: str
    total_items: int
    total_size: int
    server_name: str

    model_config = {"from_attributes": True}
