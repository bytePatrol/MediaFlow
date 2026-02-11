import asyncio
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func
from typing import List, Optional

from app.database import get_session
from app.models.worker_server import WorkerServer
from app.models.transcode_job import TranscodeJob
from app.models.job_log import JobLog
from app.schemas.server import (
    WorkerServerCreate, WorkerServerResponse, WorkerServerUpdate,
    ServerStatusResponse, AutoSetupProgress, BenchmarkResponse,
    BenchmarkTriggerResponse, ServerPickerItem, ServerEstimateResponse,
    ProvisionRequest, ProvisionTriggerResponse,
)
from app.services.worker_service import WorkerService

router = APIRouter()


@router.post("/", response_model=WorkerServerResponse)
async def add_server(data: WorkerServerCreate, session: AsyncSession = Depends(get_session)):
    service = WorkerService(session)
    server = await service.add_server(data)
    return server


@router.get("/available", response_model=List[ServerPickerItem])
async def get_available_servers(session: AsyncSession = Depends(get_session)):
    """Lightweight list of online servers with load + perf scores for the frontend picker."""
    result = await session.execute(
        select(WorkerServer).where(
            WorkerServer.is_enabled == True,  # noqa: E712
            WorkerServer.status == "online",
        ).order_by(WorkerServer.name)
    )
    servers = result.scalars().all()

    items = []
    for server in servers:
        # Count active jobs
        active_result = await session.execute(
            select(func.count()).select_from(TranscodeJob).where(
                TranscodeJob.worker_server_id == server.id,
                TranscodeJob.status.in_(["transcoding", "verifying", "replacing", "transferring"]),
            )
        )
        active_count = active_result.scalar() or 0

        # Count queued jobs
        queued_result = await session.execute(
            select(func.count()).select_from(TranscodeJob).where(
                TranscodeJob.worker_server_id == server.id,
                TranscodeJob.status == "queued",
            )
        )
        queued_count = queued_result.scalar() or 0

        # Get latest benchmark speeds
        from app.services.benchmark_service import get_latest_benchmark
        latest = await get_latest_benchmark(session, server.id)

        items.append(ServerPickerItem(
            id=server.id,
            name=server.name,
            status=server.status,
            performance_score=server.performance_score,
            active_jobs=active_count,
            queued_jobs=queued_count,
            max_concurrent_jobs=server.max_concurrent_jobs,
            cpu_model=server.cpu_model,
            gpu_model=server.gpu_model,
            upload_mbps=latest.upload_mbps if latest else None,
            download_mbps=latest.download_mbps if latest else None,
            is_local=server.is_local,
        ))

    return items


@router.get("/", response_model=List[WorkerServerResponse])
async def list_servers(session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(WorkerServer).order_by(WorkerServer.name))
    servers = result.scalars().all()
    return [WorkerServerResponse.model_validate(s) for s in servers]


@router.get("/{server_id}", response_model=WorkerServerResponse)
async def get_server(server_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(WorkerServer).where(WorkerServer.id == server_id))
    server = result.scalar_one_or_none()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    return server


@router.put("/{server_id}", response_model=WorkerServerResponse)
async def update_server(
    server_id: int, data: WorkerServerUpdate, session: AsyncSession = Depends(get_session)
):
    result = await session.execute(select(WorkerServer).where(WorkerServer.id == server_id))
    server = result.scalar_one_or_none()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(server, key, value)
    await session.commit()
    await session.refresh(server)
    return server


@router.delete("/{server_id}")
async def delete_server(server_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(WorkerServer).where(WorkerServer.id == server_id))
    server = result.scalar_one_or_none()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")
    await session.delete(server)
    await session.commit()
    return {"status": "deleted"}


@router.post("/{server_id}/test")
async def test_server_connection(server_id: int, session: AsyncSession = Depends(get_session)):
    service = WorkerService(session)
    result = await service.test_connection(server_id)
    return result


@router.get("/{server_id}/status", response_model=ServerStatusResponse)
async def get_server_status(server_id: int, session: AsyncSession = Depends(get_session)):
    service = WorkerService(session)
    return await service.get_server_status(server_id)


@router.post("/{server_id}/provision", response_model=ProvisionTriggerResponse)
async def provision_server(
    server_id: int,
    data: ProvisionRequest = ProvisionRequest(),
    session: AsyncSession = Depends(get_session),
):
    """Provision a fresh VPS with ffmpeg and dependencies (runs in background)."""
    result = await session.execute(select(WorkerServer).where(WorkerServer.id == server_id))
    server = result.scalar_one_or_none()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    if server.is_local:
        raise HTTPException(status_code=400, detail="Cannot provision the local server")

    if server.status == "provisioning":
        raise HTTPException(status_code=409, detail="Server is already being provisioned")

    from app.services.provisioning_service import run_provisioning
    asyncio.create_task(run_provisioning(server_id, install_gpu_drivers=data.install_gpu))

    return ProvisionTriggerResponse(
        status="started",
        message=f"Provisioning started for {server.name}",
    )


@router.post("/{server_id}/benchmark", response_model=BenchmarkTriggerResponse)
async def trigger_benchmark(server_id: int, session: AsyncSession = Depends(get_session)):
    """Trigger a network benchmark for a server (runs in background)."""
    result = await session.execute(select(WorkerServer).where(WorkerServer.id == server_id))
    server = result.scalar_one_or_none()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    if server.status != "online" and not server.is_local:
        raise HTTPException(status_code=400, detail="Server must be online to benchmark")

    from app.services.benchmark_service import run_benchmark
    asyncio.create_task(run_benchmark(server_id))

    return BenchmarkTriggerResponse(
        status="started",
        message=f"Benchmark started for {server.name}",
    )


@router.get("/{server_id}/benchmarks", response_model=List[BenchmarkResponse])
async def get_benchmarks(server_id: int, session: AsyncSession = Depends(get_session)):
    """Get benchmark history for a server."""
    from app.services.benchmark_service import get_benchmarks as get_bench
    benchmarks = await get_bench(session, server_id)
    return [BenchmarkResponse.model_validate(b) for b in benchmarks]


@router.get("/{server_id}/estimate", response_model=ServerEstimateResponse)
async def get_transcode_estimate(
    server_id: int,
    file_size_bytes: int = Query(..., description="Total file size in bytes"),
    duration_ms: int = Query(..., description="Total media duration in milliseconds"),
    session: AsyncSession = Depends(get_session),
):
    """Estimate transcode time for a server based on historical performance."""
    result = await session.execute(select(WorkerServer).where(WorkerServer.id == server_id))
    server = result.scalar_one_or_none()
    if not server:
        raise HTTPException(status_code=404, detail="Server not found")

    # Get average FPS from completed job logs on this server
    avg_result = await session.execute(
        select(func.avg(JobLog.avg_fps), func.count(JobLog.id))
        .where(
            JobLog.worker_server_id == server_id,
            JobLog.status == "completed",
            JobLog.avg_fps.isnot(None),
            JobLog.avg_fps > 0,
        )
    )
    row = avg_result.one()
    avg_fps = row[0]
    job_count = row[1] or 0

    # Get benchmark transfer speeds
    from app.services.benchmark_service import get_latest_benchmark
    latest_bench = await get_latest_benchmark(session, server_id)

    estimated_seconds = None
    estimated_display = "--"

    if avg_fps and avg_fps > 0:
        duration_sec = duration_ms / 1000.0
        # Frames in the file (assume 24fps source)
        total_frames = duration_sec * 24
        transcode_seconds = total_frames / avg_fps

        # Add transfer time if remote server with benchmark data
        transfer_seconds = 0
        if not server.is_local and latest_bench and latest_bench.upload_mbps:
            # Upload source + download result
            upload_time = (file_size_bytes * 8) / (latest_bench.upload_mbps * 1_000_000)
            # Assume output is ~60% of source
            download_time = (file_size_bytes * 0.6 * 8) / (latest_bench.download_mbps * 1_000_000) if latest_bench.download_mbps else 0
            transfer_seconds = upload_time + download_time

        estimated_seconds = int(transcode_seconds + transfer_seconds)
        if estimated_seconds < 60:
            estimated_display = f"~{estimated_seconds}s"
        elif estimated_seconds < 3600:
            estimated_display = f"~{estimated_seconds // 60} min"
        else:
            hours = estimated_seconds // 3600
            mins = (estimated_seconds % 3600) // 60
            estimated_display = f"~{hours}h {mins}m"

    return ServerEstimateResponse(
        server_id=server.id,
        server_name=server.name,
        estimated_seconds=estimated_seconds,
        estimated_display=estimated_display,
        based_on_jobs=job_count,
    )
