import logging
from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from typing import List
from datetime import datetime

from app.database import get_session
from app.models.webhook_source import WebhookSource
from app.schemas.webhook import WebhookSourceCreate, WebhookSourceUpdate, WebhookSourceResponse

logger = logging.getLogger(__name__)

router = APIRouter()


@router.get("/sources", response_model=List[WebhookSourceResponse])
async def list_sources(session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(WebhookSource).order_by(WebhookSource.created_at.desc()))
    return result.scalars().all()


@router.post("/sources", response_model=WebhookSourceResponse)
async def create_source(data: WebhookSourceCreate, session: AsyncSession = Depends(get_session)):
    source = WebhookSource(**data.model_dump())
    if not source.secret:
        import secrets
        source.secret = secrets.token_urlsafe(24)
    session.add(source)
    await session.commit()
    await session.refresh(source)
    return source


@router.put("/sources/{source_id}", response_model=WebhookSourceResponse)
async def update_source(source_id: int, data: WebhookSourceUpdate, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(WebhookSource).where(WebhookSource.id == source_id))
    source = result.scalar_one_or_none()
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")
    for key, value in data.model_dump(exclude_unset=True).items():
        setattr(source, key, value)
    await session.commit()
    await session.refresh(source)
    return source


@router.delete("/sources/{source_id}")
async def delete_source(source_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(WebhookSource).where(WebhookSource.id == source_id))
    source = result.scalar_one_or_none()
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")
    await session.delete(source)
    await session.commit()
    return {"status": "deleted"}


@router.post("/ingest/{source_id}")
async def ingest_webhook(source_id: int, request: Request, session: AsyncSession = Depends(get_session)):
    """Accept Sonarr/Radarr webhook payload, extract file path, create transcode job."""
    result = await session.execute(select(WebhookSource).where(WebhookSource.id == source_id))
    source = result.scalar_one_or_none()
    if not source:
        raise HTTPException(status_code=404, detail="Source not found")
    if not source.is_enabled:
        raise HTTPException(status_code=403, detail="Source is disabled")

    body = await request.json()
    logger.info(f"Webhook received from source {source.name}: {body.get('eventType', 'unknown')}")

    # Extract file path from Sonarr/Radarr payload
    file_path = None
    if "movieFile" in body:
        file_path = body["movieFile"].get("path") or body["movieFile"].get("relativePath")
    elif "episodeFile" in body:
        file_path = body["episodeFile"].get("path") or body["episodeFile"].get("relativePath")
    elif "movie" in body and "movieFile" in body.get("movie", {}):
        file_path = body["movie"]["movieFile"].get("path")

    if not file_path:
        # Update stats even if we can't extract a path
        source.events_received = (source.events_received or 0) + 1
        source.last_received_at = datetime.utcnow()
        await session.commit()
        return {"status": "ignored", "reason": "no file path found in payload"}

    # Create transcode job
    from app.models.transcode_job import TranscodeJob
    job = TranscodeJob(
        source_path=file_path,
        status="queued",
        preset_id=source.preset_id,
        priority=5,
    )
    session.add(job)

    source.events_received = (source.events_received or 0) + 1
    source.last_received_at = datetime.utcnow()
    await session.commit()
    await session.refresh(job)

    from app.api.websocket import manager
    await manager.broadcast("job.created", {"job_id": job.id, "source": "webhook"})

    return {"status": "queued", "job_id": job.id}
