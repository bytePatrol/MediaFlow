import asyncio
import logging
from datetime import datetime

from fastapi import APIRouter, HTTPException
from sqlalchemy import select, func as sql_func

from app.database import async_session_factory
from app.models.worker_server import WorkerServer
from app.models.cloud_cost import CloudCostRecord
from app.models.app_settings import AppSetting
from app.schemas.cloud import (
    CloudDeployRequest, CloudDeployResponse, CloudPlanInfo,
    CloudCostSummary, CloudCostRecordResponse,
    CloudSettingsResponse, CloudSettingsUpdate,
)

logger = logging.getLogger(__name__)
router = APIRouter()


async def _get_setting(session, key: str, default=None):
    result = await session.execute(
        select(AppSetting).where(AppSetting.key == key)
    )
    setting = result.scalar_one_or_none()
    if setting and setting.value is not None:
        return setting.value
    return default


async def _set_setting(session, key: str, value):
    result = await session.execute(
        select(AppSetting).where(AppSetting.key == key)
    )
    setting = result.scalar_one_or_none()
    if setting:
        setting.value = value
    else:
        session.add(AppSetting(key=key, value=value))


@router.post("/deploy", response_model=CloudDeployResponse)
async def deploy_cloud_gpu(request: CloudDeployRequest):
    """Deploy a new cloud GPU instance."""
    from app.services.cloud_provisioning_service import deploy_cloud_gpu as _deploy

    # Fire and forget — deployment runs in background, progress via WebSocket
    async def _run():
        try:
            await _deploy(
                plan=request.plan,
                region=request.region,
                idle_minutes=request.idle_minutes,
                auto_teardown=request.auto_teardown,
            )
        except Exception as e:
            logger.error(f"Cloud deploy background task failed: {e}")

    task = asyncio.create_task(_run())

    return CloudDeployResponse(
        status="deploying",
        server_id=0,  # Will be broadcast via WebSocket once created
        message=f"Deploying {request.plan} in {request.region}. Watch for progress via WebSocket.",
    )


@router.delete("/{server_id}")
async def teardown_cloud_instance(server_id: int):
    """Tear down a cloud GPU instance."""
    from app.services.cloud_provisioning_service import teardown_cloud_gpu

    async with async_session_factory() as session:
        result = await session.execute(
            select(WorkerServer).where(WorkerServer.id == server_id)
        )
        server = result.scalar_one_or_none()
        if not server:
            raise HTTPException(404, "Server not found")
        if not server.cloud_provider:
            raise HTTPException(400, "Server is not a cloud instance")

    asyncio.create_task(teardown_cloud_gpu(server_id))
    return {"status": "tearing_down", "server_id": server_id}


@router.get("/plans", response_model=list[CloudPlanInfo])
async def list_gpu_plans():
    """List available GPU plans with regions and pricing."""
    async with async_session_factory() as session:
        api_key = await _get_setting(session, "vultr_api_key")

    if not api_key:
        raise HTTPException(400, "Vultr API key not configured. Set it in Settings > Cloud GPU.")

    from app.services.vultr_client import VultrClient
    vultr = VultrClient(api_key)
    plans = await vultr.list_gpu_plans()
    return [CloudPlanInfo(**p) for p in plans]


@router.get("/cost-summary", response_model=CloudCostSummary)
async def get_cost_summary():
    """Get monthly cloud cost breakdown."""
    async with async_session_factory() as session:
        now = datetime.utcnow()
        month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

        # Completed cost records this month
        result = await session.execute(
            select(CloudCostRecord).where(
                CloudCostRecord.created_at >= month_start,
            ).order_by(CloudCostRecord.created_at.desc())
        )
        records = result.scalars().all()

        completed_total = sum(r.cost_usd or 0 for r in records if r.cost_usd)

        # Running instance costs
        active_result = await session.execute(
            select(WorkerServer).where(
                WorkerServer.cloud_provider.isnot(None),
                WorkerServer.cloud_status == "active",
            )
        )
        active_servers = active_result.scalars().all()
        running_cost = sum(
            (now - s.cloud_created_at).total_seconds() / 3600 * (s.hourly_cost or 0)
            for s in active_servers if s.cloud_created_at
        )

        monthly_cap = float(await _get_setting(session, "cloud_monthly_spend_cap", 100.0))
        instance_cap = float(await _get_setting(session, "cloud_instance_spend_cap", 50.0))

        return CloudCostSummary(
            current_month_total=round(completed_total + running_cost, 2),
            active_instance_running_cost=round(running_cost, 2),
            monthly_cap=monthly_cap,
            instance_cap=instance_cap,
            records=[CloudCostRecordResponse.model_validate(r) for r in records],
        )


@router.get("/settings", response_model=CloudSettingsResponse)
async def get_cloud_settings():
    """Get cloud GPU settings."""
    async with async_session_factory() as session:
        api_key = await _get_setting(session, "vultr_api_key")
        return CloudSettingsResponse(
            api_key_configured=bool(api_key),
            default_plan=await _get_setting(session, "cloud_default_plan", "vcg-a16-6c-64g-16vram"),
            default_region=await _get_setting(session, "cloud_default_region", "ewr"),
            monthly_spend_cap=float(await _get_setting(session, "cloud_monthly_spend_cap", 100.0)),
            instance_spend_cap=float(await _get_setting(session, "cloud_instance_spend_cap", 50.0)),
            default_idle_minutes=int(await _get_setting(session, "cloud_default_idle_minutes", 30)),
            auto_deploy_enabled=await _get_setting(session, "cloud_auto_deploy_enabled", "false") == "true",
        )


@router.put("/settings", response_model=CloudSettingsResponse)
async def update_cloud_settings(request: CloudSettingsUpdate):
    """Update cloud GPU settings."""
    async with async_session_factory() as session:
        if request.vultr_api_key is not None:
            # Verify the key before saving
            from app.services.vultr_client import VultrClient
            vultr = VultrClient(request.vultr_api_key)
            valid = await vultr.verify_api_key()
            if not valid:
                raise HTTPException(400, "Invalid Vultr API key")
            await _set_setting(session, "vultr_api_key", request.vultr_api_key)

        if request.default_plan is not None:
            await _set_setting(session, "cloud_default_plan", request.default_plan)
        if request.default_region is not None:
            await _set_setting(session, "cloud_default_region", request.default_region)
        if request.monthly_spend_cap is not None:
            await _set_setting(session, "cloud_monthly_spend_cap", request.monthly_spend_cap)
        if request.instance_spend_cap is not None:
            await _set_setting(session, "cloud_instance_spend_cap", request.instance_spend_cap)
        if request.default_idle_minutes is not None:
            await _set_setting(session, "cloud_default_idle_minutes", request.default_idle_minutes)
        if request.auto_deploy_enabled is not None:
            await _set_setting(session, "cloud_auto_deploy_enabled", "true" if request.auto_deploy_enabled else "false")

        await session.commit()

    return await get_cloud_settings()
