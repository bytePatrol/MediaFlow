from pydantic import BaseModel
from typing import Optional, List, Dict


class LibraryHealthCard(BaseModel):
    library_id: int
    library_title: str
    total_items: int
    total_size: int
    codec_distribution: Dict[str, int]  # {"hevc": 100, "h264": 50, ...}
    resolution_distribution: Dict[str, int]  # {"4K": 20, "1080p": 100, ...}
    optimization_pct: float  # % of items using modern codecs
    health_score: int  # 0-100
    health_grade: str  # A-F
    potential_savings: int  # bytes
    avg_bitrate: float
    hdr_count: int


class LibraryHealthReport(BaseModel):
    libraries: List[LibraryHealthCard]
    overall_score: int
    overall_grade: str
    total_potential_savings: int


class CodecMigrationEntry(BaseModel):
    date: str
    codec_distribution: Dict[str, int]
    total_items: int
    modern_codec_pct: float


class CodecMigrationResponse(BaseModel):
    current: Dict[str, int]
    current_pct: Dict[str, float]
    history: List[CodecMigrationEntry]
    total_items: int
    modern_pct: float
    library_id: Optional[int] = None


class CostAnalyticsResponse(BaseModel):
    total_cloud_cost: float
    total_jobs_cloud: int
    cost_per_gb_saved: float
    cloud_vs_local: Dict[str, float]  # {"cloud_cost": x, "local_estimated_cost": y, "savings": z}
    monthly_trend: List[Dict]  # [{"month": "2026-01", "cost": 12.50, "jobs": 5}, ...]
    monthly_projection: float


class WorkerHeatmapEntry(BaseModel):
    worker_id: int
    worker_name: str
    hour: int  # 0-23
    avg_fps: float
    job_count: int
    utilization: float  # 0-1


class WorkerHeatmapResponse(BaseModel):
    entries: List[WorkerHeatmapEntry]
    workers: List[Dict]  # [{"id": 1, "name": "..."}, ...]


class JobTimelineEntry(BaseModel):
    job_id: int
    title: str
    worker_id: Optional[int] = None
    worker_name: Optional[str] = None
    status: str
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    duration_seconds: Optional[float] = None
    source_codec: Optional[str] = None
    target_codec: Optional[str] = None


class JobTimelineResponse(BaseModel):
    jobs: List[JobTimelineEntry]
    workers: List[Dict]


class CodecStrategyAdvice(BaseModel):
    library_id: int
    library_title: str
    current_dominant_codec: str
    recommended_target: str
    avg_savings_pct: float
    total_projected_savings: int
    rationale: str


class CodecStrategyResponse(BaseModel):
    advice: List[CodecStrategyAdvice]
    resolution_recommendations: List[Dict]  # [{"resolution": "4K", "best_codec": "av1", "avg_savings": 0.55}, ...]


class OptimizeLibraryRequest(BaseModel):
    library_id: int
    preset_id: Optional[int] = None
    min_confidence: float = 0.5
    max_items: Optional[int] = None
    dry_run: bool = False


class OptimizeLibraryStatus(BaseModel):
    session_id: str
    library_id: int
    stage: str  # "syncing", "analyzing", "queuing", "transcoding", "completed", "failed", "cancelled"
    progress_pct: float
    items_queued: int = 0
    items_completed: int = 0
    items_total: int = 0
    estimated_savings: int = 0
    actual_savings: int = 0
    message: str = ""


class DismissWithReasonRequest(BaseModel):
    reason: Optional[str] = None  # "keep_4k", "keep_codec", "too_important", "other"


class VMAFResult(BaseModel):
    job_id: int
    vmaf_score: Optional[float] = None
    vmaf_model: Optional[str] = None
    quality_label: str = ""  # "Excellent", "Good", "Fair", "Poor"


class StorageSavingsProjection(BaseModel):
    current_total_size: int
    if_all_optimized: int
    potential_savings: int
    current_pace_monthly: int
    months_to_storage_limit: Optional[float] = None
    confidence_bands: List[Dict]  # [{"month": "2026-03", "low": x, "mid": y, "high": z}, ...]
