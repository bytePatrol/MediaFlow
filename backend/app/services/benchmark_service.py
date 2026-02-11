import asyncio
import logging
import os
import tempfile
import time
from datetime import datetime
from typing import Optional, List

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import async_session_factory
from app.models.worker_server import WorkerServer
from app.models.server_benchmark import ServerBenchmark
from app.api.websocket import manager

logger = logging.getLogger(__name__)

TEST_FILE_SIZE = 200_000_000  # 200 MB


async def run_benchmark(server_id: int):
    """Run a benchmark measuring SSH transfer speed to the Plex server.

    Generates a test file, measures SSH latency and SFTP upload/download speeds
    between this machine and the Plex server, computes a performance_score,
    and broadcasts progress via WebSocket.
    """
    from app.models.plex_server import PlexServer

    async with async_session_factory() as session:
        result = await session.execute(
            select(WorkerServer).where(WorkerServer.id == server_id)
        )
        server = result.scalar_one_or_none()
        if not server:
            logger.error(f"Benchmark: server {server_id} not found")
            return

        # Find the active Plex server with SSH configured
        plex_result = await session.execute(
            select(PlexServer).where(
                PlexServer.ssh_hostname.isnot(None),
                PlexServer.ssh_hostname != "",
                PlexServer.is_active == True,
            ).limit(1)
        )
        plex_server = plex_result.scalar_one_or_none()
        if not plex_server or not plex_server.ssh_hostname:
            logger.error("Benchmark: no Plex server with SSH configured")
            await manager.broadcast("benchmark.failed", {
                "server_id": server_id,
                "benchmark_id": 0,
                "error": "No Plex server with SSH configured. Set up SSH in Settings first.",
            })
            return

        benchmark = ServerBenchmark(
            worker_server_id=server_id,
            test_file_size_bytes=TEST_FILE_SIZE,
            status="running",
            started_at=datetime.utcnow(),
        )
        session.add(benchmark)
        await session.commit()
        await session.refresh(benchmark)

        await manager.broadcast("benchmark.progress", {
            "server_id": server_id,
            "benchmark_id": benchmark.id,
            "step": "started",
            "progress": 0,
        })

        try:
            from app.utils.ssh import SSHClient
            ssh = SSHClient(
                plex_server.ssh_hostname,
                plex_server.ssh_port or 22,
                plex_server.ssh_username,
                plex_server.ssh_key_path,
                plex_server.ssh_password,
            )

            # Step 1: Measure latency to Plex server
            await manager.broadcast("benchmark.progress", {
                "server_id": server_id,
                "benchmark_id": benchmark.id,
                "step": "latency",
                "progress": 10,
            })

            latency_start = time.monotonic()
            connected = await ssh.test_connection()
            latency_ms = (time.monotonic() - latency_start) * 1000
            benchmark.latency_ms = round(latency_ms, 2)

            if not connected:
                raise ConnectionError(f"SSH connection to Plex server ({plex_server.ssh_hostname}) failed")

            # Step 2: Find writable directory on Plex server and generate test file
            await manager.broadcast("benchmark.progress", {
                "server_id": server_id,
                "benchmark_id": benchmark.id,
                "step": "generating",
                "progress": 20,
            })

            tmp_dir = tempfile.mkdtemp(prefix="mediaflow_bench_")
            local_file = os.path.join(tmp_dir, "benchmark_test.bin")
            with open(local_file, "wb") as f:
                f.write(os.urandom(TEST_FILE_SIZE))

            # Try candidate directories — /tmp often has no space on NAS devices
            remote_dir = None
            for candidate in ["/share/Public/.mediaflow_benchmark", "/tmp/mediaflow_benchmark"]:
                result = await ssh.run_command(
                    f"mkdir -p {candidate} && dd if=/dev/zero of={candidate}/.probe bs=1 count=1 2>/dev/null && rm -f {candidate}/.probe && echo OK"
                )
                if "OK" in (result.get("stdout") or ""):
                    remote_dir = candidate
                    break

            if not remote_dir:
                raise IOError("No writable directory found on Plex server")

            remote_file = f"{remote_dir}/benchmark_test.bin"

            # Step 3: Upload test (backend → Plex server)
            await manager.broadcast("benchmark.progress", {
                "server_id": server_id,
                "benchmark_id": benchmark.id,
                "step": "uploading",
                "progress": 40,
            })

            upload_start = time.monotonic()
            upload_ok = await ssh.upload_file(local_file, remote_file)
            upload_elapsed = time.monotonic() - upload_start

            if not upload_ok:
                raise IOError("Upload to Plex server failed")

            upload_mbps = (TEST_FILE_SIZE * 8) / (upload_elapsed * 1_000_000)
            benchmark.upload_mbps = round(upload_mbps, 2)

            # Step 4: Download test (Plex server → backend)
            await manager.broadcast("benchmark.progress", {
                "server_id": server_id,
                "benchmark_id": benchmark.id,
                "step": "downloading",
                "progress": 70,
            })

            download_local = os.path.join(tmp_dir, "benchmark_download.bin")
            download_start = time.monotonic()
            download_ok = await ssh.download_file(remote_file, download_local)
            download_elapsed = time.monotonic() - download_start

            if not download_ok:
                raise IOError("Download from Plex server failed")

            download_mbps = (TEST_FILE_SIZE * 8) / (download_elapsed * 1_000_000)
            benchmark.download_mbps = round(download_mbps, 2)

            # Step 5: Cleanup
            await ssh.run_command(f"rm -rf {remote_dir}")
            try:
                os.remove(local_file)
                os.remove(download_local)
                os.rmdir(tmp_dir)
            except OSError:
                pass

            # Step 6: Compute performance score
            # Higher throughput = better, lower latency = better
            throughput_avg = (upload_mbps + download_mbps) / 2
            # Scale: 500 Mbps SFTP = 100 points (realistic for Gigabit LAN)
            throughput_score = min(100, (throughput_avg / 500) * 100)
            # Latency includes SSH handshake overhead (~100-300ms normal on LAN)
            # Scale: 0ms = 100, 1000ms = 0
            latency_score = max(0, 100 - (latency_ms / 10))

            performance_score = round(throughput_score * 0.85 + latency_score * 0.15, 1)
            performance_score = max(0, min(100, performance_score))

            benchmark.status = "completed"
            benchmark.completed_at = datetime.utcnow()
            server.performance_score = performance_score
            server.last_benchmark_at = datetime.utcnow()
            await session.commit()

            await manager.broadcast("benchmark.completed", {
                "server_id": server_id,
                "benchmark_id": benchmark.id,
                "performance_score": performance_score,
                "upload_mbps": benchmark.upload_mbps,
                "download_mbps": benchmark.download_mbps,
                "latency_ms": benchmark.latency_ms,
            })

        except Exception as e:
            logger.error(f"Benchmark failed for server {server_id}: {e}")
            benchmark.status = "failed"
            benchmark.error_message = str(e)[:1000]
            benchmark.completed_at = datetime.utcnow()
            await session.commit()

            await manager.broadcast("benchmark.failed", {
                "server_id": server_id,
                "benchmark_id": benchmark.id,
                "error": str(e)[:500],
            })


async def get_benchmarks(session: AsyncSession, server_id: int) -> List[ServerBenchmark]:
    result = await session.execute(
        select(ServerBenchmark)
        .where(ServerBenchmark.worker_server_id == server_id)
        .order_by(ServerBenchmark.created_at.desc())
        .limit(20)
    )
    return list(result.scalars().all())


async def get_latest_benchmark(session: AsyncSession, server_id: int) -> Optional[ServerBenchmark]:
    result = await session.execute(
        select(ServerBenchmark)
        .where(ServerBenchmark.worker_server_id == server_id)
        .order_by(ServerBenchmark.created_at.desc())
        .limit(1)
    )
    return result.scalar_one_or_none()
