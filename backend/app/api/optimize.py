import asyncio
import uuid
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_session, async_session_factory
from app.schemas.library_health import OptimizeLibraryRequest, OptimizeLibraryStatus

router = APIRouter()

# In-memory session store for optimization progress
_optimize_sessions: dict = {}


@router.post("/start")
async def start_optimize(request: OptimizeLibraryRequest, session: AsyncSession = Depends(get_session)):
    """Start one-click library optimization. Returns session_id for progress tracking."""
    session_id = str(uuid.uuid4())[:8]
    status = OptimizeLibraryStatus(
        session_id=session_id,
        library_id=request.library_id,
        stage="syncing",
        progress_pct=0.0,
        message="Starting library optimization...",
    )
    _optimize_sessions[session_id] = status

    # Launch background task
    asyncio.create_task(_run_optimization(session_id, request))

    return status


@router.get("/status/{session_id}", response_model=OptimizeLibraryStatus)
async def get_optimize_status(session_id: str):
    status = _optimize_sessions.get(session_id)
    if not status:
        raise HTTPException(status_code=404, detail="Session not found")
    return status


@router.post("/cancel/{session_id}")
async def cancel_optimize(session_id: str):
    status = _optimize_sessions.get(session_id)
    if not status:
        raise HTTPException(status_code=404, detail="Session not found")
    status.stage = "cancelled"
    status.message = "Optimization cancelled by user"
    return {"status": "cancelled"}


async def _run_optimization(session_id: str, request: OptimizeLibraryRequest):
    """Background task that chains: sync -> analyze -> queue -> monitor."""
    status = _optimize_sessions[session_id]

    try:
        async with async_session_factory() as session:
            # Stage 1: Sync
            status.stage = "syncing"
            status.progress_pct = 5.0
            status.message = "Syncing library with Plex..."

            from app.services.plex_service import PlexService
            from app.models.plex_library import PlexLibrary
            from sqlalchemy import select

            lib_result = await session.execute(
                select(PlexLibrary).where(PlexLibrary.id == request.library_id)
            )
            library = lib_result.scalar_one_or_none()
            if not library:
                status.stage = "failed"
                status.message = "Library not found"
                return

            try:
                plex_service = PlexService(session)
                await plex_service.sync_server(library.server_id)
            except Exception as e:
                pass  # Continue even if sync fails

            if status.stage == "cancelled":
                return

            # Stage 2: Analyze
            status.stage = "analyzing"
            status.progress_pct = 20.0
            status.message = "Running intelligence analysis..."

            from app.services.recommendation_service import RecommendationService
            rec_service = RecommendationService(session)
            analysis_result = await rec_service.run_library_analysis(
                library_id=request.library_id, trigger="auto_optimize"
            )

            if status.stage == "cancelled":
                return

            # Stage 3: Queue recommendations
            status.stage = "queuing"
            status.progress_pct = 40.0
            status.message = "Queuing high-confidence recommendations..."

            from app.models.recommendation import Recommendation
            from app.models.media_item import MediaItem

            query = (
                select(Recommendation)
                .join(MediaItem, Recommendation.media_item_id == MediaItem.id)
                .where(
                    MediaItem.plex_library_id == request.library_id,
                    Recommendation.is_dismissed == False,
                    Recommendation.is_actioned == False,
                    Recommendation.confidence >= request.min_confidence,
                    Recommendation.estimated_savings > 0,
                )
                .order_by(Recommendation.priority_score.desc().nullslast())
            )
            if request.max_items:
                query = query.limit(request.max_items)

            rec_result = await session.execute(query)
            recs = rec_result.scalars().all()

            if not recs:
                status.stage = "completed"
                status.progress_pct = 100.0
                status.message = "No actionable recommendations found."
                return

            rec_ids = [r.id for r in recs]
            status.items_total = len(rec_ids)
            status.estimated_savings = sum(r.estimated_savings or 0 for r in recs)

            if request.dry_run:
                status.stage = "completed"
                status.progress_pct = 100.0
                status.items_queued = len(rec_ids)
                status.message = f"Dry run complete. Would queue {len(rec_ids)} items."
                return

            # Queue them
            from app.schemas.recommendation import BatchQueueRequest
            batch_request = BatchQueueRequest(
                recommendation_ids=rec_ids,
                preset_id=request.preset_id,
            )
            queue_result = await rec_service.batch_queue(batch_request)
            status.items_queued = queue_result.get("jobs_created", 0)

            if status.stage == "cancelled":
                return

            # Stage 4: Monitor (simplified - just mark as transcoding)
            status.stage = "transcoding"
            status.progress_pct = 60.0
            status.message = f"Queued {status.items_queued} jobs for transcoding. Monitor progress in Processing view."

            # Broadcast via WebSocket
            try:
                from app.api.websocket import manager
                await manager.broadcast("optimize.started", {
                    "session_id": session_id,
                    "library_id": request.library_id,
                    "items_queued": status.items_queued,
                    "estimated_savings": status.estimated_savings,
                })
            except Exception:
                pass

            status.stage = "completed"
            status.progress_pct = 100.0
            status.message = f"Optimization complete! Queued {status.items_queued} jobs."

    except Exception as e:
        status.stage = "failed"
        status.message = f"Optimization failed: {str(e)}"
