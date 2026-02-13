from typing import Optional, Dict, Any
from pydantic import BaseModel
from datetime import datetime


class FilterPresetCreate(BaseModel):
    name: str
    filter_json: Dict[str, Any] = {}


class FilterPresetUpdate(BaseModel):
    name: Optional[str] = None
    filter_json: Optional[Dict[str, Any]] = None


class FilterPresetResponse(BaseModel):
    id: int
    name: str
    filter_json: Optional[Dict[str, Any]] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    model_config = {"from_attributes": True}
