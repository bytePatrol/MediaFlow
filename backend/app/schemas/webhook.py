from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class WebhookSourceCreate(BaseModel):
    name: str
    source_type: str = "sonarr"
    secret: Optional[str] = None
    preset_id: Optional[int] = None
    is_enabled: bool = True


class WebhookSourceUpdate(BaseModel):
    name: Optional[str] = None
    source_type: Optional[str] = None
    secret: Optional[str] = None
    preset_id: Optional[int] = None
    is_enabled: Optional[bool] = None


class WebhookSourceResponse(BaseModel):
    id: int
    name: str
    source_type: str
    secret: Optional[str] = None
    preset_id: Optional[int] = None
    is_enabled: bool = True
    last_received_at: Optional[datetime] = None
    events_received: int = 0
    created_at: Optional[datetime] = None

    model_config = {"from_attributes": True}
