from pydantic import BaseModel
from typing import Optional, List, Dict, Any
from datetime import datetime


class AutomationRuleCreate(BaseModel):
    name: str
    trigger_type: str  # analysis_complete, job_complete, job_failed, library_sync, storage_threshold, schedule
    conditions_json: Optional[List[Dict[str, Any]]] = None
    actions_json: Optional[List[Dict[str, Any]]] = None
    is_enabled: bool = True


class AutomationRuleUpdate(BaseModel):
    name: Optional[str] = None
    trigger_type: Optional[str] = None
    conditions_json: Optional[List[Dict[str, Any]]] = None
    actions_json: Optional[List[Dict[str, Any]]] = None
    is_enabled: Optional[bool] = None


class AutomationRuleResponse(BaseModel):
    id: int
    name: str
    is_enabled: bool
    trigger_type: str
    conditions_json: Optional[List[Dict[str, Any]]] = None
    actions_json: Optional[List[Dict[str, Any]]] = None
    last_triggered_at: Optional[datetime] = None
    trigger_count: int = 0
    created_at: Optional[datetime] = None

    model_config = {"from_attributes": True}
