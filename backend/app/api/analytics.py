from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from app.database import get_session
from app.services.analytics_service import AnalyticsService
from app.schemas.analytics import (
    AnalyticsOverview, StorageBreakdown, CodecDistribution,
    ResolutionDistribution, SavingsHistoryPoint, JobHistoryEntry,
)

router = APIRouter()


@router.get("/overview", response_model=AnalyticsOverview)
async def get_overview(session: AsyncSession = Depends(get_session)):
    service = AnalyticsService(session)
    return await service.get_overview()


@router.get("/storage")
async def get_storage_breakdown(session: AsyncSession = Depends(get_session)):
    service = AnalyticsService(session)
    return await service.get_storage_breakdown()


@router.get("/codec-distribution")
async def get_codec_distribution(session: AsyncSession = Depends(get_session)):
    service = AnalyticsService(session)
    return await service.get_codec_distribution()


@router.get("/resolution-distribution")
async def get_resolution_distribution(session: AsyncSession = Depends(get_session)):
    service = AnalyticsService(session)
    return await service.get_resolution_distribution()


@router.get("/savings-history")
async def get_savings_history(
    days: int = Query(30, ge=1, le=365),
    session: AsyncSession = Depends(get_session),
):
    service = AnalyticsService(session)
    return await service.get_savings_history(days=days)


@router.get("/job-history")
async def get_job_history(
    page: int = Query(1, ge=1),
    page_size: int = Query(50, ge=1, le=200),
    session: AsyncSession = Depends(get_session),
):
    service = AnalyticsService(session)
    return await service.get_job_history(page=page, page_size=page_size)
