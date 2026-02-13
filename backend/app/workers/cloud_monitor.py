import asyncio
import logging
from datetime import datetime

from sqlalchemy import select, func as sql_func

from app.database import async_session_factory
from app.models.worker_server import WorkerServer
from app.models.transcode_job import TranscodeJob
from app.models.cloud_cost import CloudCostRecord
from app.models.app_settings import AppSetting
from app.api.websocket import manager

logger = logging.getLogger(__name__)


class CloudMonitorWorker:
    def __init__(self, interval: int = 60):
        self.interval = interval
        self.running = False

    async def start(self):
        self.running = True
        logger.info("CloudMonitorWorker started")
        # Run orphan check on startup
        await self._check_orphans()
        while self.running:
            try:
                await self._check_cloud_instances()
            except Exception as e:
                logger.error(f"CloudMonitorWorker error: {e}")
            await asyncio.sleep(self.interval)

    async def stop(self):
        self.running = False
        logger.info("CloudMonitorWorker stopping — checking for active cloud instances")
        await self._warn_active_instances()

    async def _get_setting(self, session, key: str, default=None):
        result = await session.execute(
            select(AppSetting).where(AppSetting.key == key)
        )
        setting = result.scalar_one_or_none()
        if setting and setting.value is not None:
            return setting.value
        return default

    async def _check_cloud_instances(self):
        async with async_session_factory() as session:
            # Get all active cloud workers
            result = await session.execute(
                select(WorkerServer).where(
                    WorkerServer.cloud_provider.isnot(None),
                    WorkerServer.cloud_status == "active",
                )
            )
            cloud_servers = result.scalars().all()

            if not cloud_servers:
                return

            monthly_cap = float(await self._get_setting(session, "cloud_monthly_spend_cap", 100.0))
            instance_cap = float(await self._get_setting(session, "cloud_instance_spend_cap", 50.0))

            # Calculate current month's spend
            now = datetime.utcnow()
            month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)

            result = await session.execute(
                select(sql_func.coalesce(sql_func.sum(CloudCostRecord.cost_usd), 0)).where(
                    CloudCostRecord.created_at >= month_start,
                    CloudCostRecord.cost_usd.isnot(None),
                )
            )
            completed_spend = float(result.scalar())

            for server in cloud_servers:
                if not server.cloud_created_at:
                    continue

                running_hours = (now - server.cloud_created_at).total_seconds() / 3600
                running_cost = running_hours * (server.hourly_cost or 0)

                # Check instance spend cap
                if running_cost >= instance_cap:
                    logger.warning(
                        f"Cloud server {server.id}: instance spend cap reached "
                        f"(${running_cost:.2f} >= ${instance_cap:.2f})"
                    )
                    await manager.broadcast("cloud.spend_cap_reached", {
                        "server_id": server.id,
                        "cap_type": "instance",
                        "current_cost": round(running_cost, 2),
                        "cap": instance_cap,
                    })
                    from app.utils.notify import fire_notification
                    await fire_notification("cloud.spend_cap_reached", {
                        "server_id": server.id,
                        "cap_type": "instance",
                        "current_cost": round(running_cost, 2),
                        "cap": instance_cap,
                    })
                    await self._auto_teardown(server.id)
                    continue

                # Check monthly spend cap
                total_running_cost = completed_spend + sum(
                    (now - s.cloud_created_at).total_seconds() / 3600 * (s.hourly_cost or 0)
                    for s in cloud_servers if s.cloud_created_at
                )
                if total_running_cost >= monthly_cap:
                    logger.warning(
                        f"Monthly cloud spend cap reached (${total_running_cost:.2f} >= ${monthly_cap:.2f})"
                    )
                    await manager.broadcast("cloud.spend_cap_reached", {
                        "server_id": server.id,
                        "cap_type": "monthly",
                        "current_cost": round(total_running_cost, 2),
                        "cap": monthly_cap,
                    })
                    from app.utils.notify import fire_notification
                    await fire_notification("cloud.spend_cap_reached", {
                        "server_id": server.id,
                        "cap_type": "monthly",
                        "current_cost": round(total_running_cost, 2),
                        "cap": monthly_cap,
                    })
                    await self._auto_teardown(server.id)
                    continue

                # Check idle timeout
                if not server.cloud_auto_teardown:
                    continue

                idle_minutes = server.cloud_idle_minutes or 30

                # Check if any jobs are active on this worker
                job_result = await session.execute(
                    select(TranscodeJob).where(
                        TranscodeJob.worker_server_id == server.id,
                        TranscodeJob.status.in_(["transcoding", "transferring", "queued"]),
                    ).limit(1)
                )
                active_job = job_result.scalar_one_or_none()

                if active_job:
                    continue  # Worker is busy, skip idle check

                # Find last completed job time
                last_job_result = await session.execute(
                    select(TranscodeJob.completed_at).where(
                        TranscodeJob.worker_server_id == server.id,
                        TranscodeJob.completed_at.isnot(None),
                    ).order_by(TranscodeJob.completed_at.desc()).limit(1)
                )
                last_completed = last_job_result.scalar_one_or_none()

                # Use instance creation time if no jobs have completed
                idle_since = last_completed or server.cloud_created_at
                if idle_since:
                    idle_seconds = (now - idle_since).total_seconds()
                    if idle_seconds >= idle_minutes * 60:
                        logger.info(
                            f"Cloud server {server.id}: idle for {idle_seconds/60:.0f} min "
                            f"(timeout: {idle_minutes} min) — auto-tearing down"
                        )
                        await self._auto_teardown(server.id)

    async def _auto_teardown(self, server_id: int):
        """Trigger auto-teardown of a cloud instance."""
        try:
            from app.services.cloud_provisioning_service import teardown_cloud_gpu
            await teardown_cloud_gpu(server_id)
        except Exception as e:
            logger.error(f"Auto-teardown failed for server {server_id}: {e}")

    async def _check_orphans(self):
        """On startup, check for Vultr instances labeled 'mediaflow-*' that don't match any server."""
        try:
            async with async_session_factory() as session:
                api_key = await self._get_setting(session, "vultr_api_key")
                if not api_key:
                    return

                from app.services.vultr_client import VultrClient
                vultr = VultrClient(api_key)
                instances = await vultr.list_instances(label_filter="mediaflow-gpu-")

                # Get all known instance IDs
                result = await session.execute(
                    select(WorkerServer.cloud_instance_id).where(
                        WorkerServer.cloud_instance_id.isnot(None),
                    )
                )
                known_ids = {row[0] for row in result.fetchall()}

                for inst in instances:
                    if inst["id"] not in known_ids:
                        logger.warning(
                            f"Orphan cloud instance detected: {inst['id']} ({inst.get('label')}). Destroying."
                        )
                        try:
                            await vultr.delete_instance(inst["id"])
                        except Exception as e:
                            logger.error(f"Failed to destroy orphan {inst['id']}: {e}")

        except Exception as e:
            logger.debug(f"Orphan check skipped: {e}")

    async def _warn_active_instances(self):
        """On shutdown, warn about any active cloud instances still running."""
        async with async_session_factory() as session:
            result = await session.execute(
                select(WorkerServer).where(
                    WorkerServer.cloud_provider.isnot(None),
                    WorkerServer.cloud_status == "active",
                )
            )
            active = result.scalars().all()
            if active:
                logger.warning(
                    f"{len(active)} cloud GPU instance(s) still running! "
                    "They will continue to incur charges. "
                    "Tear them down manually or restart the app."
                )
                for s in active:
                    logger.warning(f"  - Server {s.id}: {s.hostname} ({s.cloud_plan})")
