from fastapi import APIRouter, Depends, Query
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional
import io

from app.database import get_session
from app.services.analytics_service import AnalyticsService
from app.services.report_service import ReportService
from app.schemas.analytics import (
    AnalyticsOverview, StorageBreakdown, CodecDistribution,
    ResolutionDistribution, SavingsHistoryPoint, JobHistoryEntry,
    TrendsResponse, PredictionResponse, ServerPerformance,
    HealthScoreResponse, SavingsOpportunity,
)

router = APIRouter()


@router.get("/report/pdf")
async def get_health_report_pdf(session: AsyncSession = Depends(get_session)):
    service = ReportService(session)
    pdf_bytes = await service.generate_health_report()
    return StreamingResponse(
        io.BytesIO(pdf_bytes),
        media_type="application/pdf",
        headers={
            "Content-Disposition": 'attachment; filename="mediaflow-health-report.pdf"'
        },
    )


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


@router.get("/trends", response_model=TrendsResponse)
async def get_trends(
    days: int = Query(30, ge=7, le=365),
    session: AsyncSession = Depends(get_session),
):
    service = AnalyticsService(session)
    return await service.get_trends(days=days)


@router.get("/predictions", response_model=PredictionResponse)
async def get_predictions(session: AsyncSession = Depends(get_session)):
    service = AnalyticsService(session)
    return await service.get_predictions()


@router.get("/server-performance")
async def get_server_performance(session: AsyncSession = Depends(get_session)):
    service = AnalyticsService(session)
    return await service.get_server_performance()


@router.get("/health-score", response_model=HealthScoreResponse)
async def get_health_score(session: AsyncSession = Depends(get_session)):
    service = AnalyticsService(session)
    return await service.get_health_score()


@router.get("/top-opportunities")
async def get_top_opportunities(session: AsyncSession = Depends(get_session)):
    service = AnalyticsService(session)
    return await service.get_top_opportunities()
