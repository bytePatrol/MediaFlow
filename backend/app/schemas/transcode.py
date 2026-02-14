from pydantic import BaseModel
from typing import Optional, List, Any
from datetime import datetime


class TranscodePresetResponse(BaseModel):
    id: int
    name: str
    description: Optional[str] = None
    is_builtin: bool = False
    video_codec: str = "libx265"
    target_resolution: Optional[str] = None
    bitrate_mode: str = "crf"
    crf_value: Optional[int] = None
    target_bitrate: Optional[str] = None
    hw_accel: Optional[str] = None
    audio_mode: str = "copy"
    audio_codec: Optional[str] = None
    container: str = "mkv"
    subtitle_mode: str = "copy"
    custom_flags: Optional[str] = None
    hdr_mode: str = "preserve"
    two_pass: bool = False
    encoder_tune: Optional[str] = None

    model_config = {"from_attributes": True}


class TranscodePresetCreate(BaseModel):
    name: str
    description: Optional[str] = None
    video_codec: str = "libx265"
    target_resolution: Optional[str] = None
    bitrate_mode: str = "crf"
    crf_value: Optional[int] = 23
    target_bitrate: Optional[str] = None
    hw_accel: Optional[str] = None
    audio_mode: str = "copy"
    audio_codec: Optional[str] = None
    container: str = "mkv"
    subtitle_mode: str = "copy"
    custom_flags: Optional[str] = None
    hdr_mode: str = "preserve"
    two_pass: bool = False
    encoder_tune: Optional[str] = None


class TranscodePresetUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    video_codec: Optional[str] = None
    target_resolution: Optional[str] = None
    bitrate_mode: Optional[str] = None
    crf_value: Optional[int] = None
    target_bitrate: Optional[str] = None
    hw_accel: Optional[str] = None
    audio_mode: Optional[str] = None
    audio_codec: Optional[str] = None
    container: Optional[str] = None
    subtitle_mode: Optional[str] = None
    custom_flags: Optional[str] = None
    hdr_mode: Optional[str] = None
    two_pass: Optional[bool] = None
    encoder_tune: Optional[str] = None


class TranscodeJobCreate(BaseModel):
    media_item_ids: List[int]
    preset_id: Optional[int] = None
    config: Optional[dict] = None
    priority: int = 0
    is_dry_run: bool = False
    scheduled_after: Optional[datetime] = None
    preferred_worker_id: Optional[int] = None


class TranscodeJobResponse(BaseModel):
    id: int
    media_item_id: Optional[int] = None
    preset_id: Optional[int] = None
    worker_server_id: Optional[int] = None
    config_json: Optional[Any] = None
    status: str
    status_detail: Optional[str] = None
    priority: int = 0
    progress_percent: float = 0.0
    current_fps: Optional[float] = None
    eta_seconds: Optional[int] = None
    source_path: Optional[str] = None
    source_size: Optional[int] = None
    output_path: Optional[str] = None
    output_size: Optional[int] = None
    ffmpeg_command: Optional[str] = None
    ffmpeg_log: Optional[str] = None
    is_dry_run: bool = False
    created_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    media_title: Optional[str] = None
    cloud_cost_usd: Optional[float] = None
    retry_count: int = 0
    max_retries: int = 3
    validation_status: Optional[str] = None

    model_config = {"from_attributes": True}


class TranscodeJobUpdate(BaseModel):
    status: Optional[str] = None
    priority: Optional[int] = None
    worker_server_id: Optional[int] = None


class QueueStatsResponse(BaseModel):
    total_queued: int
    total_active: int
    total_completed: int
    total_failed: int
    aggregate_fps: float
    estimated_total_time: int
    available_workers: int = 0


class DryRunResponse(BaseModel):
    ffmpeg_command: str
    estimated_output_size: Optional[int] = None
    estimated_duration: Optional[int] = None
    estimated_reduction_percent: Optional[float] = None


class ProbeRequest(BaseModel):
    file_path: str


class ProbeResponse(BaseModel):
    file_path: str
    file_size: int
    duration_seconds: float
    video_codec: Optional[str] = None
    resolution: Optional[str] = None
    bitrate: Optional[int] = None
    audio_codec: Optional[str] = None
    audio_channels: Optional[int] = None


class ManualTranscodeRequest(BaseModel):
    file_path: str
    file_size: Optional[int] = None
    config: Optional[dict] = None
    preset_id: Optional[int] = None
    priority: int = 10
    preferred_worker_id: Optional[int] = None
