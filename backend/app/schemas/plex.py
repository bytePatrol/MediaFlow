from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class PlexConnectRequest(BaseModel):
    url: str
    token: str
    name: Optional[str] = None


class PlexServerResponse(BaseModel):
    id: int
    name: str
    url: str
    machine_id: Optional[str] = None
    version: Optional[str] = None
    is_active: bool
    last_synced_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    library_count: int = 0
    ssh_hostname: Optional[str] = None
    ssh_port: int = 22
    ssh_username: Optional[str] = None
    ssh_key_path: Optional[str] = None
    ssh_password: Optional[str] = None

    model_config = {"from_attributes": True}


class PlexLibraryResponse(BaseModel):
    id: int
    plex_server_id: int
    plex_key: str
    title: str
    type: str
    total_items: int = 0
    total_size: int = 0

    model_config = {"from_attributes": True}


class PlexSyncResponse(BaseModel):
    status: str
    items_synced: int
    libraries_synced: int
    duration_seconds: float


class PlexPinCreateResponse(BaseModel):
    pin_id: int
    auth_url: str


class PlexAuthStatusResponse(BaseModel):
    status: str  # "pending", "authenticated", "expired", "error"
    auth_token: Optional[str] = None
    servers_discovered: int = 0
    error_message: Optional[str] = None


class PlexServerSSHUpdate(BaseModel):
    ssh_hostname: Optional[str] = None
    ssh_port: int = 22
    ssh_username: Optional[str] = None
    ssh_key_path: Optional[str] = None
    ssh_password: Optional[str] = None


class PlexOAuthServersResponse(BaseModel):
    status: str
    servers: List[PlexServerResponse]
