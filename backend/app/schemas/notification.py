from typing import Optional, List, Dict, Any
from pydantic import BaseModel


class NotificationConfigCreate(BaseModel):
    type: str
    name: str
    config: Dict[str, Any] = {}
    events: List[str] = []
    is_enabled: bool = True


class NotificationConfigUpdate(BaseModel):
    name: Optional[str] = None
    config: Optional[Dict[str, Any]] = None
    events: Optional[List[str]] = None
    is_enabled: Optional[bool] = None


class NotificationConfigResponse(BaseModel):
    id: int
    type: str
    name: str
    config_json: Optional[Dict[str, Any]] = None
    events: Optional[List[str]] = None
    is_enabled: bool

    model_config = {"from_attributes": True}
