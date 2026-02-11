from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from app.database import get_session
from app.schemas.transcode import (
    TranscodeJobCreate, TranscodeJobResponse, TranscodeJobUpdate,
    QueueStatsResponse, DryRunResponse,
)
from app.services.transcode_service import TranscodeService
from app.api.websocket import manager

router = APIRouter()


@router.post("/jobs")
async def create_transcode_jobs(
    request: TranscodeJobCreate,
    session: AsyncSession = Depends(get_session),
):
    service = TranscodeService(session)
    jobs = await service.create_jobs(request)
    return {"status": "created", "jobs_created": len(jobs), "job_ids": [j.id for j in jobs]}


@router.get("/jobs")
async def list_transcode_jobs(
    status: Optional[str] = None,
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    session: AsyncSession = Depends(get_session),
):
    service = TranscodeService(session)
    return await service.get_jobs(status=status, page=page, page_size=page_size)


@router.get("/jobs/{job_id}", response_model=TranscodeJobResponse)
async def get_transcode_job(job_id: int, session: AsyncSession = Depends(get_session)):
    service = TranscodeService(session)
    job = await service.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return job


@router.patch("/jobs/{job_id}")
async def update_transcode_job(
    job_id: int,
    update: TranscodeJobUpdate,
    session: AsyncSession = Depends(get_session),
):
    service = TranscodeService(session)
    job = await service.update_job(job_id, update)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    # If cancelling, tell the worker to kill the active process
    if update.status == "cancelled":
        from app.workers.scheduler import get_transcode_worker
        worker = get_transcode_worker()
        if worker:
            await worker.cancel_job(job_id)
        await manager.broadcast("job.status_changed", {
            "job_id": job.id, "status": "cancelled"
        })

    return {"status": "updated", "job_id": job.id, "new_status": job.status}


@router.delete("/jobs/finished")
async def clear_finished_jobs(
    include_active: bool = False,
    session: AsyncSession = Depends(get_session),
):
    service = TranscodeService(session)
    if include_active:
        # Cancel any running worker processes first
        from app.workers.scheduler import get_transcode_worker
        worker = get_transcode_worker()
        if worker:
            active_jobs = await service.get_active_job_ids()
            for job_id in active_jobs:
                await worker.cancel_job(job_id)
    count = await service.clear_finished_jobs(include_active=include_active)
    return {"status": "cleared", "deleted": count}


@router.delete("/cache")
async def clear_transcode_cache():
    """Delete leftover temp files from failed/cancelled transcodes."""
    import os
    import shutil
    working_dir = "/tmp/mediaflow"
    if not os.path.exists(working_dir):
        return {"status": "cleared", "files_deleted": 0, "bytes_freed": 0}

    files_deleted = 0
    bytes_freed = 0
    for entry in os.listdir(working_dir):
        path = os.path.join(working_dir, entry)
        try:
            size = os.path.getsize(path)
            if os.path.isfile(path):
                os.remove(path)
            elif os.path.isdir(path):
                shutil.rmtree(path)
            files_deleted += 1
            bytes_freed += size
        except OSError:
            pass
    return {"status": "cleared", "files_deleted": files_deleted, "bytes_freed": bytes_freed}


@router.get("/queue/stats", response_model=QueueStatsResponse)
async def get_queue_stats(session: AsyncSession = Depends(get_session)):
    service = TranscodeService(session)
    return await service.get_queue_stats()


@router.post("/dry-run", response_model=DryRunResponse)
async def dry_run_transcode(
    media_item_id: int,
    preset_id: Optional[int] = None,
    config: Optional[dict] = None,
    session: AsyncSession = Depends(get_session),
):
    service = TranscodeService(session)
    return await service.dry_run(media_item_id, preset_id=preset_id, config=config)
