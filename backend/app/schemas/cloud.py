from pydantic import BaseModel
from typing import Optional
from datetime import datetime


class CloudDeployRequest(BaseModel):
    plan: str = "vcg-a16-6c-64g-16vram"
    region: str = "ewr"
    idle_minutes: int = 30
    auto_teardown: bool = True


class CloudDeployResponse(BaseModel):
    status: str
    server_id: int
    message: str


class CloudPlanInfo(BaseModel):
    plan_id: str
    gpu_model: str
    vcpus: int
    ram_mb: int
    gpu_vram_gb: int
    monthly_cost: float
    hourly_cost: float
    regions: list[str]


class CloudCostRecordResponse(BaseModel):
    id: int
    worker_server_id: Optional[int] = None
    job_id: Optional[int] = None
    cloud_provider: str
    cloud_instance_id: str
    cloud_plan: str
    hourly_rate: float
    start_time: datetime
    end_time: Optional[datetime] = None
    duration_seconds: Optional[float] = None
    cost_usd: Optional[float] = None
    record_type: str
    created_at: Optional[datetime] = None

    model_config = {"from_attributes": True}


class CloudCostSummary(BaseModel):
    current_month_total: float
    active_instance_running_cost: float
    monthly_cap: float
    instance_cap: float
    records: list[CloudCostRecordResponse]


class CloudSettingsResponse(BaseModel):
    api_key_configured: bool
    default_plan: str
    default_region: str
    monthly_spend_cap: float
    instance_spend_cap: float
    default_idle_minutes: int
    auto_deploy_enabled: bool


class CloudSettingsUpdate(BaseModel):
    vultr_api_key: Optional[str] = None
    default_plan: Optional[str] = None
    default_region: Optional[str] = None
    monthly_spend_cap: Optional[float] = None
    instance_spend_cap: Optional[float] = None
    default_idle_minutes: Optional[int] = None
    auto_deploy_enabled: Optional[bool] = None
