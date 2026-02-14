from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class WatchFolderCreate(BaseModel):
    path: str
    preset_id: Optional[int] = None
    extensions: str = "mkv,mp4,avi,mov,ts,m4v,wmv"
    delay_seconds: int = 30
    is_enabled: bool = True


class WatchFolderUpdate(BaseModel):
    path: Optional[str] = None
    preset_id: Optional[int] = None
    extensions: Optional[str] = None
    delay_seconds: Optional[int] = None
    is_enabled: Optional[bool] = None


class WatchFolderResponse(BaseModel):
    id: int
    path: str
    preset_id: Optional[int] = None
    extensions: str = "mkv,mp4,avi,mov,ts,m4v,wmv"
    delay_seconds: int = 30
    is_enabled: bool = True
    last_scan_at: Optional[datetime] = None
    files_processed: int = 0
    created_at: Optional[datetime] = None

    model_config = {"from_attributes": True}
