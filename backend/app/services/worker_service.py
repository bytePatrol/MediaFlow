import logging
from typing import Optional, Dict, Any

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.models.worker_server import WorkerServer
from app.models.transcode_job import TranscodeJob
from app.schemas.server import WorkerServerCreate, WorkerServerResponse, ServerStatusResponse

logger = logging.getLogger(__name__)


class WorkerService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def add_server(self, data: WorkerServerCreate) -> WorkerServer:
        server = WorkerServer(**data.model_dump())
        server.status = "online" if data.is_local else "pending"
        self.session.add(server)
        await self.session.commit()
        await self.session.refresh(server)
        return server

    async def test_connection(self, server_id: int) -> Dict[str, Any]:
        result = await self.session.execute(
            select(WorkerServer).where(WorkerServer.id == server_id)
        )
        server = result.scalar_one_or_none()
        if not server:
            return {"status": "error", "message": "Server not found"}

        if server.is_local:
            server.status = "online"
            await self.session.commit()
            return {"status": "success", "message": "Local server is available"}

        try:
            from app.utils.ssh import SSHClient
            ssh = SSHClient(server.hostname, server.port,
                          server.ssh_username, server.ssh_key_path)
            connected = await ssh.test_connection()
            if connected:
                capabilities = await ssh.probe_capabilities()
                server.cpu_model = capabilities.get("cpu_model")
                server.cpu_cores = capabilities.get("cpu_cores")
                server.ram_gb = capabilities.get("ram_gb")
                server.gpu_model = capabilities.get("gpu_model")
                server.hw_accel_types = capabilities.get("hw_accel_types", [])
                server.status = "online"
                await self.session.commit()
                return {"status": "success", "message": "Connection established", "capabilities": capabilities}
            else:
                return {"status": "error", "message": "SSH connection failed"}
        except Exception as e:
            logger.error(f"Connection test failed: {e}")
            return {"status": "error", "message": str(e)}

    async def get_server_status(self, server_id: int) -> ServerStatusResponse:
        result = await self.session.execute(
            select(WorkerServer).where(WorkerServer.id == server_id)
        )
        server = result.scalar_one_or_none()
        if not server:
            raise ValueError("Server not found")

        # Pull real metrics from health_worker cache
        from app.workers.health_worker import get_server_metrics
        metrics = get_server_metrics(server_id) or {}

        # Count active jobs
        active_result = await self.session.execute(
            select(func.count()).select_from(TranscodeJob).where(
                TranscodeJob.worker_server_id == server_id,
                TranscodeJob.status.in_(["transcoding", "verifying", "replacing", "transferring"]),
            )
        )
        active_count = active_result.scalar() or 0

        # Count queued jobs
        queued_result = await self.session.execute(
            select(func.count()).select_from(TranscodeJob).where(
                TranscodeJob.worker_server_id == server_id,
                TranscodeJob.status == "queued",
            )
        )
        queued_count = queued_result.scalar() or 0

        # Get benchmark data
        from app.services.benchmark_service import get_latest_benchmark
        latest_bench = await get_latest_benchmark(self.session, server_id)

        return ServerStatusResponse(
            id=server.id,
            name=server.name,
            status=server.status,
            cpu_percent=metrics.get("cpu_percent"),
            gpu_percent=metrics.get("gpu_percent"),
            ram_used_gb=metrics.get("ram_used_gb"),
            ram_total_gb=metrics.get("ram_total_gb", server.ram_gb),
            gpu_temp=metrics.get("gpu_temp"),
            fan_speed=metrics.get("fan_speed"),
            active_jobs=active_count,
            queued_jobs=queued_count,
            upload_mbps=latest_bench.upload_mbps if latest_bench else None,
            download_mbps=latest_bench.download_mbps if latest_bench else None,
            performance_score=server.performance_score,
        )
