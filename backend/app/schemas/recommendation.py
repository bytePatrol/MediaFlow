from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class RecommendationResponse(BaseModel):
    id: int
    media_item_id: Optional[int] = None
    type: str
    severity: str
    title: str
    description: Optional[str] = None
    estimated_savings: Optional[int] = None
    suggested_preset_id: Optional[int] = None
    is_dismissed: bool = False
    is_actioned: bool = False
    priority_score: Optional[float] = None
    confidence: Optional[float] = None
    analysis_run_id: Optional[int] = None
    created_at: Optional[datetime] = None
    media_title: Optional[str] = None
    media_file_size: Optional[int] = None

    model_config = {"from_attributes": True}


class RecommendationSummary(BaseModel):
    total: int
    by_type: dict
    total_estimated_savings: int
    dismissed_count: int
    actioned_count: int


class BatchQueueRequest(BaseModel):
    recommendation_ids: List[int]
    preset_id: Optional[int] = None


class AnalysisRunResponse(BaseModel):
    id: int
    started_at: Optional[str] = None
    completed_at: Optional[str] = None
    total_items_analyzed: int = 0
    recommendations_generated: int = 0
    total_estimated_savings: int = 0
    trigger: str = "manual"


class SavingsCodecEntry(BaseModel):
    source_codec: str
    target_codec: str
    jobs: int
    original_size: int = 0
    final_size: int = 0
    saved: int = 0


class SavingsAchievedResponse(BaseModel):
    total_jobs: int = 0
    total_original_size: int = 0
    total_final_size: int = 0
    total_saved: int = 0
    by_codec: List[SavingsCodecEntry] = []
