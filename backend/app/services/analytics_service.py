import logging
from typing import Optional, List, Dict, Any
from datetime import datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.models.media_item import MediaItem
from app.models.transcode_job import TranscodeJob
from app.models.job_log import JobLog
from app.models.worker_server import WorkerServer
from app.schemas.analytics import (
    AnalyticsOverview, StorageBreakdown, CodecDistribution,
    ResolutionDistribution,
)

logger = logging.getLogger(__name__)


class AnalyticsService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def get_overview(self) -> AnalyticsOverview:
        size_result = await self.session.execute(select(func.sum(MediaItem.file_size)))
        total_size = size_result.scalar() or 0

        count_result = await self.session.execute(select(func.count()).select_from(MediaItem))
        total_items = count_result.scalar() or 0

        active_result = await self.session.execute(
            select(func.count()).select_from(TranscodeJob)
            .where(TranscodeJob.status == "transcoding")
        )
        active = active_result.scalar() or 0

        completed_result = await self.session.execute(
            select(func.count()).select_from(TranscodeJob)
            .where(TranscodeJob.status == "completed")
        )
        completed = completed_result.scalar() or 0

        savings_result = await self.session.execute(
            select(func.sum(JobLog.source_size - JobLog.target_size))
            .where(JobLog.status == "completed", JobLog.target_size.isnot(None))
        )
        total_savings = savings_result.scalar() or 0

        time_result = await self.session.execute(
            select(func.sum(JobLog.duration_seconds))
            .where(JobLog.status == "completed")
        )
        total_time = time_result.scalar() or 0.0

        h264_result = await self.session.execute(
            select(func.sum(MediaItem.file_size))
            .where(MediaItem.video_codec.in_(["h264", "mpeg4", "vc1"]))
        )
        potential = int((h264_result.scalar() or 0) * 0.4)

        avg_ratio = 0.0
        if completed > 0:
            ratio_result = await self.session.execute(
                select(func.avg(JobLog.size_reduction))
                .where(JobLog.status == "completed", JobLog.size_reduction.isnot(None))
            )
            avg_ratio = ratio_result.scalar() or 0.0

        return AnalyticsOverview(
            total_media_size=total_size,
            total_items=total_items,
            potential_savings=potential,
            active_transcodes=active,
            completed_transcodes=completed,
            total_savings_achieved=total_savings,
            avg_compression_ratio=float(avg_ratio),
            total_transcode_time=float(total_time),
        )

    async def get_storage_breakdown(self) -> StorageBreakdown:
        result = await self.session.execute(
            select(MediaItem.video_codec, func.sum(MediaItem.file_size))
            .group_by(MediaItem.video_codec)
            .order_by(func.sum(MediaItem.file_size).desc())
        )
        rows = result.all()
        total = sum(r[1] or 0 for r in rows)
        colors = ["#256af4", "#22c55e", "#f59e0b", "#ef4444", "#8b5cf6", "#6b7280"]

        return StorageBreakdown(
            labels=[r[0] or "unknown" for r in rows],
            values=[r[1] or 0 for r in rows],
            percentages=[round((r[1] or 0) / max(total, 1) * 100, 1) for r in rows],
            colors=colors[:len(rows)],
        )

    async def get_codec_distribution(self) -> CodecDistribution:
        result = await self.session.execute(
            select(MediaItem.video_codec, func.count(), func.sum(MediaItem.file_size))
            .group_by(MediaItem.video_codec)
            .order_by(func.count().desc())
        )
        rows = result.all()
        return CodecDistribution(
            codecs=[r[0] or "unknown" for r in rows],
            counts=[r[1] for r in rows],
            sizes=[r[2] or 0 for r in rows],
        )

    async def get_resolution_distribution(self) -> ResolutionDistribution:
        result = await self.session.execute(
            select(MediaItem.resolution_tier, func.count(), func.sum(MediaItem.file_size))
            .group_by(MediaItem.resolution_tier)
            .order_by(func.count().desc())
        )
        rows = result.all()
        return ResolutionDistribution(
            resolutions=[r[0] or "unknown" for r in rows],
            counts=[r[1] for r in rows],
            sizes=[r[2] or 0 for r in rows],
        )

    async def get_savings_history(self, days: int = 30) -> List[Dict[str, Any]]:
        since = datetime.utcnow() - timedelta(days=days)
        result = await self.session.execute(
            select(JobLog)
            .where(JobLog.status == "completed", JobLog.created_at >= since)
            .order_by(JobLog.created_at.asc())
        )
        logs = result.scalars().all()

        history = []
        cumulative = 0
        for log in logs:
            savings = (log.source_size or 0) - (log.target_size or 0)
            cumulative += max(savings, 0)
            history.append({
                "date": log.created_at.isoformat() if log.created_at else "",
                "savings": max(savings, 0),
                "cumulative_savings": cumulative,
            })
        return history

    async def get_job_history(self, page: int = 1, page_size: int = 50) -> Dict[str, Any]:
        count_result = await self.session.execute(
            select(func.count()).select_from(JobLog)
        )
        total = count_result.scalar() or 0

        offset = (page - 1) * page_size
        result = await self.session.execute(
            select(JobLog)
            .order_by(JobLog.created_at.desc())
            .offset(offset).limit(page_size)
        )
        logs = result.scalars().all()

        items = []
        for log in logs:
            items.append({
                "id": log.id,
                "title": log.title or "",
                "source_codec": log.source_codec,
                "target_codec": log.target_codec,
                "source_size": log.source_size,
                "target_size": log.target_size,
                "savings": (log.source_size or 0) - (log.target_size or 0) if log.target_size else None,
                "duration_seconds": log.duration_seconds,
                "status": log.status,
                "completed_at": log.created_at.isoformat() if log.created_at else None,
            })

        return {"items": items, "total": total, "page": page, "page_size": page_size}
