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
    last_triggered_at: Optional[str] = None
    trigger_count: int = 0

    model_config = {"from_attributes": True}


NOTIFICATION_EVENTS = {
    "job.completed": "When a transcode job finishes successfully",
    "job.failed": "When a transcode job fails",
    "analysis.completed": "When intelligence analysis completes",
    "server.offline": "When a worker server goes offline",
    "server.online": "When a worker server comes back online",
    "cloud.deploy_completed": "When a cloud GPU instance is ready",
    "cloud.teardown_completed": "When a cloud GPU is destroyed",
    "cloud.spend_cap_reached": "When cloud spend exceeds the cap",
    "queue.stalled": "When jobs are waiting but no workers are available",
    "sync.completed": "When a Plex library sync finishes",
}


class NotificationEventInfo(BaseModel):
    event: str
    description: str
