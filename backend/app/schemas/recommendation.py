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
