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
