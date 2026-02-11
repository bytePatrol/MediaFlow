from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, update
from typing import Optional, List

from app.database import get_session
from app.models.recommendation import Recommendation
from app.schemas.recommendation import RecommendationResponse, RecommendationSummary, BatchQueueRequest
from app.services.recommendation_service import RecommendationService

router = APIRouter()


@router.get("/", response_model=List[RecommendationResponse])
async def list_recommendations(
    type: Optional[str] = None,
    include_dismissed: bool = False,
    session: AsyncSession = Depends(get_session),
):
    service = RecommendationService(session)
    return await service.get_recommendations(type=type, include_dismissed=include_dismissed)


@router.get("/summary", response_model=RecommendationSummary)
async def get_recommendation_summary(session: AsyncSession = Depends(get_session)):
    service = RecommendationService(session)
    return await service.get_summary()


@router.post("/generate")
async def generate_recommendations(session: AsyncSession = Depends(get_session)):
    service = RecommendationService(session)
    count = await service.run_full_analysis()
    return {"status": "completed", "recommendations_generated": count}


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
