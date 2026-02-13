from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime


class AnalyticsOverview(BaseModel):
    total_media_size: int
    total_items: int
    potential_savings: int
    active_transcodes: int
    completed_transcodes: int
    total_savings_achieved: int
    avg_compression_ratio: float
    total_transcode_time: float
    libraries_synced: int = 0
    workers_online: int = 0
    last_analysis_date: Optional[str] = None


class StorageBreakdown(BaseModel):
    labels: List[str]
    values: List[int]
    percentages: List[float]
    colors: List[str]


class CodecDistribution(BaseModel):
    codecs: List[str]
    counts: List[int]
    sizes: List[int]


class ResolutionDistribution(BaseModel):
    resolutions: List[str]
    counts: List[int]
    sizes: List[int]


class SavingsHistoryPoint(BaseModel):
    date: str
    savings: int
    cumulative_savings: int
    jobs_completed: int = 0


class JobHistoryEntry(BaseModel):
    id: int
    title: str
    source_codec: Optional[str] = None
    target_codec: Optional[str] = None
    source_size: Optional[int] = None
    target_size: Optional[int] = None
    savings: Optional[int] = None
    duration_seconds: Optional[float] = None
    status: str
    completed_at: Optional[datetime] = None
    worker_name: Optional[str] = None


class TrendData(BaseModel):
    metric: str
    current_value: float
    previous_value: float
    change_pct: float
    direction: str  # "up", "down", "flat"

class TrendsResponse(BaseModel):
    period_days: int
    trends: List[TrendData]

class PredictionResponse(BaseModel):
    daily_rate: float
    predicted_30d: float
    predicted_90d: float
    predicted_365d: float
    confidence: float

class ServerPerformance(BaseModel):
    server_id: int
    server_name: str
    total_jobs: int
    avg_fps: Optional[float] = None
    avg_compression: Optional[float] = None
    total_time_hours: float
    failure_rate: float
    is_cloud: bool

class HealthScoreResponse(BaseModel):
    score: int
    modern_codec_pct: float
    bitrate_pct: float
    container_pct: float
    audio_pct: float
    grade: str

class SavingsOpportunity(BaseModel):
    media_item_id: int
    title: str
    file_size: int
    estimated_savings: int
    current_codec: Optional[str] = None
    recommended_codec: str
