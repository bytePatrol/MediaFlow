from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from typing import Optional, List

from app.database import get_session
from app.models.recommendation import Recommendation
from app.schemas.recommendation import (
    RecommendationResponse, RecommendationSummary, BatchQueueRequest,
    AnalysisRunResponse, SavingsAchievedResponse,
)
from app.schemas.library_health import DismissWithReasonRequest
from app.services.recommendation_service import RecommendationService

router = APIRouter()


@router.get("/", response_model=List[RecommendationResponse])
async def list_recommendations(
    type: Optional[str] = None,
    include_dismissed: bool = False,
    library_id: Optional[int] = None,
    session: AsyncSession = Depends(get_session),
):
    service = RecommendationService(session)
    return await service.get_recommendations(type=type, include_dismissed=include_dismissed, library_id=library_id)


@router.get("/summary", response_model=RecommendationSummary)
async def get_recommendation_summary(
    library_id: Optional[int] = None,
    session: AsyncSession = Depends(get_session),
):
    service = RecommendationService(session)
    return await service.get_summary(library_id=library_id)


@router.get("/history")
async def get_analysis_history(
    limit: int = 20,
    session: AsyncSession = Depends(get_session),
):
    service = RecommendationService(session)
    return await service.get_analysis_history(limit=limit)


@router.get("/savings", response_model=SavingsAchievedResponse)
async def get_savings_achieved(session: AsyncSession = Depends(get_session)):
    service = RecommendationService(session)
    return await service.get_savings_achieved()


@router.post("/generate")
async def generate_recommendations(session: AsyncSession = Depends(get_session)):
    service = RecommendationService(session)
    result = await service.run_full_analysis(trigger="manual")
    return {
        "status": "completed",
        "recommendations_generated": result["recommendations_generated"],
        "run_id": result["run_id"],
        "total_items_analyzed": result["total_items_analyzed"],
        "total_estimated_savings": result["total_estimated_savings"],
    }


@router.post("/analyze/{library_id}")
async def analyze_library(library_id: int, session: AsyncSession = Depends(get_session)):
    """Run analysis for a specific library."""
    service = RecommendationService(session)
    result = await service.run_library_analysis(library_id=library_id, trigger="manual")
    return {
        "status": "completed",
        "library_id": result["library_id"],
        "recommendations_generated": result["recommendations_generated"],
        "run_id": result["run_id"],
        "total_items_analyzed": result["total_items_analyzed"],
        "total_estimated_savings": result["total_estimated_savings"],
    }


@router.post("/{rec_id}/dismiss")
async def dismiss_recommendation(rec_id: int, session: AsyncSession = Depends(get_session)):
    result = await session.execute(select(Recommendation).where(Recommendation.id == rec_id))
    rec = result.scalar_one_or_none()
    if not rec:
        raise HTTPException(status_code=404, detail="Recommendation not found")
    rec.is_dismissed = True
    await session.commit()
    return {"status": "dismissed"}


@router.post("/batch-queue")
async def batch_queue_recommendations(
    request: BatchQueueRequest,
    session: AsyncSession = Depends(get_session),
):
    service = RecommendationService(session)
    result = await service.batch_queue(request)
    return result


@router.post("/{rec_id}/dismiss-with-reason")
async def dismiss_with_reason(rec_id: int, request: DismissWithReasonRequest, session: AsyncSession = Depends(get_session)):
    """Dismiss a recommendation and track the reason for learning."""
    from app.models.media_item import MediaItem
    from app.models.recommendation_feedback import RecommendationFeedback

    result = await session.execute(select(Recommendation).where(Recommendation.id == rec_id))
    rec = result.scalar_one_or_none()
    if not rec:
        raise HTTPException(status_code=404, detail="Recommendation not found")
    rec.is_dismissed = True
    rec.dismiss_reason = request.reason

    # Enrich feedback with media item metadata for better preference learning
    source_codec = None
    resolution = None
    if rec.media_item_id:
        item_result = await session.execute(
            select(MediaItem.video_codec, MediaItem.resolution_tier)
            .where(MediaItem.id == rec.media_item_id)
        )
        item_row = item_result.first()
        if item_row:
            source_codec = item_row[0]
            resolution = item_row[1]

    # Record feedback for learning
    feedback = RecommendationFeedback(
        recommendation_id=rec.id,
        media_item_id=rec.media_item_id,
        action="dismissed",
        dismiss_reason=request.reason,
        estimated_savings=rec.estimated_savings,
        source_codec=source_codec,
        target_codec=None,
        resolution=resolution,
    )
    session.add(feedback)
    await session.commit()
    return {"status": "dismissed", "reason": request.reason}
