import asyncio
import logging
import re
import subprocess
from datetime import datetime
from typing import Dict, Optional

from sqlalchemy import select

from app.database import async_session_factory
from app.models.worker_server import WorkerServer
from app.api.websocket import manager

logger = logging.getLogger(__name__)

# Module-level metrics cache: server_id -> metrics dict
_server_metrics: Dict[int, dict] = {}

AUTO_DISABLE_THRESHOLD = 5  # consecutive failures before auto-disable


def get_server_metrics(server_id: int) -> Optional[dict]:
    return _server_metrics.get(server_id)


def get_all_server_metrics() -> Dict[int, dict]:
    return dict(_server_metrics)


def _parse_float(val: str, default: float = 0.0) -> float:
    try:
        return float(val.strip())
    except (ValueError, AttributeError):
        return default


async def _collect_local_metrics() -> dict:
    """Collect metrics from the local machine (macOS compatible)."""
    metrics = {}
    loop = asyncio.get_event_loop()

    # CPU usage via top (macOS)
    try:
        result = await loop.run_in_executor(None, lambda: subprocess.run(
            ["top", "-l", "1", "-n", "0"],
            capture_output=True, text=True, timeout=10
        ))
        for line in result.stdout.splitlines():
            if "CPU usage" in line:
                # "CPU usage: 12.5% user, 8.3% sys, 79.1% idle"
                parts = line.split(",")
                for part in parts:
                    if "idle" in part:
                        idle = _parse_float(part.split("%")[0].strip().split()[-1])
                        metrics["cpu_percent"] = round(100 - idle, 1)
                break
    except Exception:
        pass

    # RAM via vm_stat + sysctl (macOS)
    try:
        result = await loop.run_in_executor(None, lambda: subprocess.run(
            ["sysctl", "-n", "hw.memsize"],
            capture_output=True, text=True, timeout=5
        ))
        total_bytes = int(result.stdout.strip())
        metrics["ram_total_gb"] = round(total_bytes / (1024**3), 2)

        result2 = await loop.run_in_executor(None, lambda: subprocess.run(
            ["vm_stat"],
            capture_output=True, text=True, timeout=5
        ))
        page_size = 16384  # default on Apple Silicon
        pages_free = 0
        pages_inactive = 0
        pages_speculative = 0
        for line in result2.stdout.splitlines():
            if "page size of" in line:
                page_size = int(line.split()[-2])
            elif "Pages free" in line:
                pages_free = int(line.split()[-1].rstrip("."))
            elif "Pages inactive" in line:
                pages_inactive = int(line.split()[-1].rstrip("."))
            elif "Pages speculative" in line:
                pages_speculative = int(line.split()[-1].rstrip("."))

        free_bytes = (pages_free + pages_inactive + pages_speculative) * page_size
        used_bytes = total_bytes - free_bytes
        metrics["ram_used_gb"] = round(max(0, used_bytes) / (1024**3), 2)
    except Exception:
        pass

    # GPU utilization via ioreg (Apple Silicon)
    try:
        result = await loop.run_in_executor(None, lambda: subprocess.run(
            ["ioreg", "-r", "-c", "AGXAccelerator", "-d", "1", "-w", "0"],
            capture_output=True, text=True, timeout=5
        ))
        match = re.search(r'"Device Utilization %"=(\d+)', result.stdout)
        if match:
            metrics["gpu_percent"] = float(match.group(1))
    except Exception:
        pass
    if "gpu_percent" not in metrics:
        metrics["gpu_percent"] = None

    # Temperature from battery sensor (centidegrees C) — best available without root
    try:
        result = await loop.run_in_executor(None, lambda: subprocess.run(
            ["ioreg", "-r", "-c", "AppleSmartBattery", "-w", "0"],
            capture_output=True, text=True, timeout=5
        ))
        for line in result.stdout.splitlines():
            stripped = line.strip()
            if stripped.startswith('"Temperature"'):
                raw = stripped.split("=")[-1].strip()
                temp_c = _parse_float(raw) / 100.0
                if 10 < temp_c < 120:
                    metrics["gpu_temp"] = round(temp_c, 1)
                break
    except Exception:
        pass
    if "gpu_temp" not in metrics:
        metrics["gpu_temp"] = None

    metrics["fan_speed"] = None

    return metrics


async def _collect_remote_metrics(server: WorkerServer) -> dict:
    """Collect metrics from a remote server via SSH."""
    metrics = {}
    try:
        from app.utils.ssh import SSHClient
        ssh = SSHClient(server.hostname, server.port,
                        server.ssh_username, server.ssh_key_path)

        # Detect OS first
        os_result = await ssh.run_command("uname -s")
        is_macos = os_result["stdout"].strip() == "Darwin"

        # CPU
        if is_macos:
            cpu_result = await ssh.run_command("top -l 1 -n 0 | grep 'CPU usage'")
            if cpu_result["exit_status"] == 0:
                line = cpu_result["stdout"]
                for part in line.split(","):
                    if "idle" in part:
                        idle = _parse_float(part.split("%")[0].strip().split()[-1])
                        metrics["cpu_percent"] = round(100 - idle, 1)
        else:
            cpu_result = await ssh.run_command("top -bn1 | grep 'Cpu(s)'")
            if cpu_result["exit_status"] == 0:
                # "Cpu(s):  5.3 us,  2.1 sy, ... 92.0 id,"
                line = cpu_result["stdout"]
                for part in line.split(","):
                    if "id" in part:
                        idle = _parse_float(part.strip().split()[0])
                        metrics["cpu_percent"] = round(100 - idle, 1)

        # RAM
        if is_macos:
            ram_result = await ssh.run_command("sysctl -n hw.memsize")
            if ram_result["exit_status"] == 0:
                total = int(ram_result["stdout"].strip())
                metrics["ram_total_gb"] = round(total / (1024**3), 2)
        else:
            ram_result = await ssh.run_command(
                "free -b | awk '/^Mem:/{printf \"%.2f %.2f\", $3/1073741824, $2/1073741824}'"
            )
            if ram_result["exit_status"] == 0:
                parts = ram_result["stdout"].strip().split()
                if len(parts) == 2:
                    metrics["ram_used_gb"] = _parse_float(parts[0])
                    metrics["ram_total_gb"] = _parse_float(parts[1])

        # GPU (nvidia-smi)
        gpu_result = await ssh.run_command(
            "nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,fan.speed "
            "--format=csv,noheader,nounits 2>/dev/null"
        )
        if gpu_result["exit_status"] == 0 and gpu_result["stdout"].strip():
            parts = gpu_result["stdout"].strip().split(",")
            if len(parts) >= 2:
                metrics["gpu_percent"] = _parse_float(parts[0])
                metrics["gpu_temp"] = _parse_float(parts[1])
            if len(parts) >= 3:
                metrics["fan_speed"] = int(_parse_float(parts[2]))

    except Exception as e:
        logger.debug(f"Failed to collect metrics for {server.name}: {e}")

    return metrics


class HealthWorker:
    def __init__(self, interval: int = 30):
        self.interval = interval
        self.running = True

    async def start(self):
        logger.info("HealthWorker started")
        while self.running:
            try:
                await self._check_servers()
            except Exception as e:
                logger.error(f"Health check error: {e}")
            await asyncio.sleep(self.interval)

    async def stop(self):
        self.running = False

    async def _check_servers(self):
        async with async_session_factory() as session:
            result = await session.execute(
                select(WorkerServer).where(WorkerServer.is_enabled == True)  # noqa: E712
            )
            servers = result.scalars().all()

            for server in servers:
                if server.is_local:
                    server.status = "online"
                    server.last_heartbeat_at = datetime.utcnow()
                    server.consecutive_failures = 0

                    metrics = await _collect_local_metrics()
                    _server_metrics[server.id] = metrics

                    await manager.broadcast("server.metrics", {
                        "server_id": server.id,
                        "status": "online",
                        **metrics,
                    })
                else:
                    try:
                        from app.utils.ssh import SSHClient
                        ssh = SSHClient(server.hostname, server.port,
                                        server.ssh_username, server.ssh_key_path)
                        connected = await ssh.test_connection()

                        if connected:
                            was_offline = server.status == "offline"
                            server.status = "online"
                            server.last_heartbeat_at = datetime.utcnow()
                            server.consecutive_failures = 0

                            metrics = await _collect_remote_metrics(server)
                            _server_metrics[server.id] = metrics

                            await manager.broadcast("server.metrics", {
                                "server_id": server.id,
                                "status": "online",
                                **metrics,
                            })

                            if was_offline:
                                from app.utils.notify import fire_notification
                                asyncio.ensure_future(fire_notification("server.online", {
                                    "server_id": server.id,
                                    "server_name": server.name,
                                }))
                        else:
                            await self._handle_failure(server, session)
                    except Exception:
                        await self._handle_failure(server, session)

            await session.commit()

        await self._check_stuck_jobs()

    async def _check_stuck_jobs(self):
        """Detect and handle jobs stuck in transcoding state."""
        async with async_session_factory() as session:
            from app.models.transcode_job import TranscodeJob
            from datetime import timedelta

            # Load configurable timeout (default 30 minutes)
            from app.models.app_settings import AppSetting
            timeout_result = await session.execute(
                select(AppSetting).where(AppSetting.key == "transcode.stuck_timeout_minutes")
            )
            timeout_setting = timeout_result.scalar_one_or_none()
            timeout_minutes = int(timeout_setting.value) if timeout_setting and timeout_setting.value else 30

            cutoff = datetime.utcnow() - timedelta(minutes=timeout_minutes)
            result = await session.execute(
                select(TranscodeJob).where(
                    TranscodeJob.status == "transcoding",
                    TranscodeJob.updated_at < cutoff,
                )
            )
            stuck_jobs = result.scalars().all()

            for job in stuck_jobs:
                logger.warning(f"Job {job.id} detected as stuck (no update for {timeout_minutes}m)")
                if (job.retry_count or 0) < (job.max_retries or 3):
                    job.retry_count = (job.retry_count or 0) + 1
                    job.status = "queued"
                    job.progress_percent = 0.0
                    job.current_fps = None
                    job.eta_seconds = None
                    job.worker_server_id = None
                    await manager.broadcast("job.stuck", {
                        "job_id": job.id,
                        "action": "requeued",
                        "retry_count": job.retry_count,
                    })
                else:
                    job.status = "failed"
                    job.status_detail = f"Stuck: no progress for {timeout_minutes} minutes"
                    await manager.broadcast("job.stuck", {
                        "job_id": job.id,
                        "action": "failed",
                    })

                from app.utils.notify import fire_notification
                import asyncio as _asyncio
                _asyncio.ensure_future(fire_notification("job.stuck", {
                    "job_id": job.id,
                    "media_title": getattr(job, 'media_title', None) or f"Job #{job.id}",
                }))

            if stuck_jobs:
                await session.commit()

    async def _handle_failure(self, server: WorkerServer, session):
        """Track consecutive failures and auto-disable after threshold."""
        if server.status == "online":
            server.status = "offline"
            await manager.broadcast("server.status", {
                "server_id": server.id,
                "status": "offline",
            })
            from app.utils.notify import fire_notification
            import asyncio as _asyncio
            _asyncio.ensure_future(fire_notification("server.offline", {
                "server_id": server.id,
                "server_name": server.name,
            }))

        server.consecutive_failures = (server.consecutive_failures or 0) + 1
        _server_metrics.pop(server.id, None)

        if server.consecutive_failures >= AUTO_DISABLE_THRESHOLD:
            server.is_enabled = False
            logger.warning(
                f"Server {server.name} auto-disabled after "
                f"{server.consecutive_failures} consecutive failures"
            )
            await manager.broadcast("server.auto_disabled", {
                "server_id": server.id,
                "name": server.name,
                "consecutive_failures": server.consecutive_failures,
            })
