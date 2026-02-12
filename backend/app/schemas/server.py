from pydantic import BaseModel
from typing import Optional, List
from datetime import datetime


class PathMappingEntry(BaseModel):
    source_prefix: str
    target_prefix: str


class WorkerServerCreate(BaseModel):
    name: str
    hostname: str
    port: int = 22
    ssh_username: Optional[str] = None
    ssh_key_path: Optional[str] = None
    role: str = "transcode"
    max_concurrent_jobs: int = 1
    is_local: bool = False
    working_directory: str = "/tmp/mediaflow"
    path_mappings: Optional[List[PathMappingEntry]] = None


class WorkerServerResponse(BaseModel):
    id: int
    name: str
    hostname: str
    port: int
    ssh_username: Optional[str] = None
    role: str
    gpu_model: Optional[str] = None
    cpu_model: Optional[str] = None
    cpu_cores: Optional[int] = None
    ram_gb: Optional[float] = None
    hw_accel_types: Optional[List[str]] = None
    max_concurrent_jobs: int = 1
    status: str
    last_heartbeat_at: Optional[datetime] = None
    hourly_cost: Optional[float] = None
    is_local: bool = False
    is_enabled: bool = True
    working_directory: str
    path_mappings: Optional[List[PathMappingEntry]] = None
    active_jobs: int = 0
    performance_score: Optional[float] = None
    last_benchmark_at: Optional[datetime] = None
    # Cloud GPU fields
    cloud_provider: Optional[str] = None
    cloud_instance_id: Optional[str] = None
    cloud_plan: Optional[str] = None
    cloud_region: Optional[str] = None
    cloud_created_at: Optional[datetime] = None
    cloud_auto_teardown: bool = True
    cloud_idle_minutes: int = 30
    cloud_status: Optional[str] = None
    cloud_idle_since: Optional[datetime] = None

    model_config = {"from_attributes": True}


class WorkerServerUpdate(BaseModel):
    name: Optional[str] = None
    hostname: Optional[str] = None
    port: Optional[int] = None
    ssh_username: Optional[str] = None
    ssh_key_path: Optional[str] = None
    max_concurrent_jobs: Optional[int] = None
    is_enabled: Optional[bool] = None
    working_directory: Optional[str] = None
    path_mappings: Optional[List[PathMappingEntry]] = None


class ServerStatusResponse(BaseModel):
    id: int
    name: str
    status: str
    cpu_percent: Optional[float] = None
    gpu_percent: Optional[float] = None
    ram_used_gb: Optional[float] = None
    ram_total_gb: Optional[float] = None
    gpu_temp: Optional[float] = None
    fan_speed: Optional[int] = None
    active_jobs: int = 0
    queued_jobs: int = 0
    uptime_percent: Optional[float] = None
    upload_mbps: Optional[float] = None
    download_mbps: Optional[float] = None
    performance_score: Optional[float] = None


class BenchmarkResponse(BaseModel):
    id: int
    worker_server_id: int
    upload_mbps: Optional[float] = None
    download_mbps: Optional[float] = None
    latency_ms: Optional[float] = None
    test_file_size_bytes: int = 200_000_000
    status: str
    error_message: Optional[str] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    created_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class BenchmarkTriggerResponse(BaseModel):
    status: str
    benchmark_id: Optional[int] = None
    message: str


class ServerPickerItem(BaseModel):
    id: int
    name: str
    status: str
    performance_score: Optional[float] = None
    active_jobs: int = 0
    queued_jobs: int = 0
    max_concurrent_jobs: int = 1
    cpu_model: Optional[str] = None
    gpu_model: Optional[str] = None
    upload_mbps: Optional[float] = None
    download_mbps: Optional[float] = None
    is_local: bool = False


class ServerEstimateResponse(BaseModel):
    server_id: int
    server_name: str
    estimated_seconds: Optional[int] = None
    estimated_display: str = "--"
    based_on_jobs: int = 0


class AutoSetupProgress(BaseModel):
    step: str
    status: str
    message: str
    progress_percent: float


class ProvisionRequest(BaseModel):
    install_gpu: bool = False


class ProvisionTriggerResponse(BaseModel):
    status: str
    message: str
