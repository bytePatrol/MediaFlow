import logging
from typing import Optional, List, Dict, Any
from datetime import datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, case

from app.models.media_item import MediaItem
from app.models.transcode_job import TranscodeJob
from app.models.job_log import JobLog
from app.models.worker_server import WorkerServer
from app.models.plex_library import PlexLibrary
from app.models.recommendation import Recommendation, AnalysisRun
from app.schemas.analytics import (
    AnalyticsOverview, StorageBreakdown, CodecDistribution,
    ResolutionDistribution, TrendData, TrendsResponse, PredictionResponse,
    ServerPerformance, HealthScoreResponse, SavingsOpportunity,
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

        libraries_result = await self.session.execute(
            select(func.count()).select_from(PlexLibrary)
        )
        libraries_synced = libraries_result.scalar() or 0

        workers_result = await self.session.execute(
            select(func.count()).select_from(WorkerServer)
            .where(WorkerServer.status == "online")
        )
        workers_online = workers_result.scalar() or 0

        analysis_result = await self.session.execute(
            select(AnalysisRun.completed_at)
            .order_by(AnalysisRun.completed_at.desc())
            .limit(1)
        )
        last_analysis = analysis_result.scalar()
        last_analysis_date = last_analysis.isoformat() if last_analysis else None

        return AnalyticsOverview(
            total_media_size=total_size,
            total_items=total_items,
            potential_savings=potential,
            active_transcodes=active,
            completed_transcodes=completed,
            total_savings_achieved=total_savings,
            avg_compression_ratio=float(avg_ratio),
            total_transcode_time=float(total_time),
            libraries_synced=libraries_synced,
            workers_online=workers_online,
            last_analysis_date=last_analysis_date,
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
            select(
                func.date(JobLog.created_at).label("day"),
                func.sum(JobLog.source_size - JobLog.target_size).label("day_savings"),
                func.count().label("jobs_completed"),
            )
            .where(JobLog.status == "completed", JobLog.target_size.isnot(None),
                   JobLog.created_at >= since)
            .group_by(func.date(JobLog.created_at))
            .order_by(func.date(JobLog.created_at).asc())
        )
        rows = result.all()

        history = []
        cumulative = 0
        for day, day_savings, jobs_completed in rows:
            savings = max(int(day_savings or 0), 0)
            cumulative += savings
            history.append({
                "date": str(day),
                "savings": savings,
                "cumulative_savings": cumulative,
                "jobs_completed": jobs_completed,
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

    async def get_trends(self, days: int = 30) -> TrendsResponse:
        now = datetime.utcnow()
        current_start = now - timedelta(days=days)
        previous_start = current_start - timedelta(days=days)

        trends = []

        # Items added
        current_items = (await self.session.execute(
            select(func.count()).select_from(MediaItem)
            .where(MediaItem.created_at >= current_start)
        )).scalar() or 0
        previous_items = (await self.session.execute(
            select(func.count()).select_from(MediaItem)
            .where(MediaItem.created_at >= previous_start, MediaItem.created_at < current_start)
        )).scalar() or 0
        trends.append(self._make_trend("items_added", current_items, previous_items))

        # Storage saved
        current_savings = (await self.session.execute(
            select(func.sum(JobLog.source_size - JobLog.target_size))
            .where(JobLog.status == "completed", JobLog.target_size.isnot(None),
                   JobLog.created_at >= current_start)
        )).scalar() or 0
        previous_savings = (await self.session.execute(
            select(func.sum(JobLog.source_size - JobLog.target_size))
            .where(JobLog.status == "completed", JobLog.target_size.isnot(None),
                   JobLog.created_at >= previous_start, JobLog.created_at < current_start)
        )).scalar() or 0
        trends.append(self._make_trend("storage_saved", current_savings, previous_savings))

        # Jobs completed
        current_jobs = (await self.session.execute(
            select(func.count()).select_from(JobLog)
            .where(JobLog.status == "completed", JobLog.created_at >= current_start)
        )).scalar() or 0
        previous_jobs = (await self.session.execute(
            select(func.count()).select_from(JobLog)
            .where(JobLog.status == "completed",
                   JobLog.created_at >= previous_start, JobLog.created_at < current_start)
        )).scalar() or 0
        trends.append(self._make_trend("jobs_completed", current_jobs, previous_jobs))

        # Avg compression ratio
        current_ratio = (await self.session.execute(
            select(func.avg(JobLog.size_reduction))
            .where(JobLog.status == "completed", JobLog.size_reduction.isnot(None),
                   JobLog.created_at >= current_start)
        )).scalar() or 0
        previous_ratio = (await self.session.execute(
            select(func.avg(JobLog.size_reduction))
            .where(JobLog.status == "completed", JobLog.size_reduction.isnot(None),
                   JobLog.created_at >= previous_start, JobLog.created_at < current_start)
        )).scalar() or 0
        trends.append(self._make_trend("avg_compression", float(current_ratio), float(previous_ratio)))

        return TrendsResponse(period_days=days, trends=trends)

    @staticmethod
    def _make_trend(metric: str, current: float, previous: float) -> TrendData:
        if previous == 0:
            change_pct = 100.0 if current > 0 else 0.0
        else:
            change_pct = round(((current - previous) / abs(previous)) * 100, 1)
        if change_pct > 1:
            direction = "up"
        elif change_pct < -1:
            direction = "down"
        else:
            direction = "flat"
        return TrendData(
            metric=metric,
            current_value=float(current),
            previous_value=float(previous),
            change_pct=change_pct,
            direction=direction,
        )

    async def get_predictions(self) -> PredictionResponse:
        # Calculate daily savings rate from last 30 days
        since = datetime.utcnow() - timedelta(days=30)
        result = await self.session.execute(
            select(func.sum(JobLog.source_size - JobLog.target_size), func.count())
            .where(JobLog.status == "completed", JobLog.target_size.isnot(None),
                   JobLog.created_at >= since)
        )
        row = result.first()
        total_savings = row[0] or 0
        job_count = row[1] or 0

        days_active = 30
        daily_rate = total_savings / max(days_active, 1)
        confidence = min(1.0, job_count / 20)  # More jobs = higher confidence

        return PredictionResponse(
            daily_rate=daily_rate,
            predicted_30d=daily_rate * 30,
            predicted_90d=daily_rate * 90,
            predicted_365d=daily_rate * 365,
            confidence=round(confidence, 2),
        )

    async def get_server_performance(self) -> List[ServerPerformance]:
        result = await self.session.execute(
            select(
                JobLog.worker_server_id,
                func.count(),
                func.avg(JobLog.avg_fps),
                func.avg(JobLog.size_reduction),
                func.sum(JobLog.duration_seconds),
                func.sum(case((JobLog.status == "failed", 1), else_=0)),
            )
            .where(JobLog.worker_server_id.isnot(None))
            .group_by(JobLog.worker_server_id)
        )
        rows = result.all()

        performances = []
        for ws_id, total, avg_fps, avg_comp, total_secs, failures in rows:
            # Look up server name
            srv_result = await self.session.execute(
                select(WorkerServer.name, WorkerServer.cloud_provider)
                .where(WorkerServer.id == ws_id)
            )
            srv_row = srv_result.first()
            server_name = srv_row[0] if srv_row else f"Server #{ws_id}"
            is_cloud = bool(srv_row[1]) if srv_row else False

            performances.append(ServerPerformance(
                server_id=ws_id,
                server_name=server_name,
                total_jobs=total,
                avg_fps=round(float(avg_fps), 1) if avg_fps else None,
                avg_compression=round(float(avg_comp), 3) if avg_comp else None,
                total_time_hours=round(float(total_secs or 0) / 3600, 2),
                failure_rate=round(float(failures or 0) / max(total, 1), 3),
                is_cloud=is_cloud,
            ))
        return performances

    async def get_health_score(self) -> HealthScoreResponse:
        total_result = await self.session.execute(select(func.count()).select_from(MediaItem))
        total = total_result.scalar() or 0
        if total == 0:
            return HealthScoreResponse(score=100, modern_codec_pct=100, bitrate_pct=100,
                                       container_pct=100, audio_pct=100, grade="A")

        # Modern codecs (hevc, h265, av1) = good
        modern_result = await self.session.execute(
            select(func.count()).select_from(MediaItem)
            .where(MediaItem.video_codec.in_(["hevc", "h265", "av1"]))
        )
        modern_count = modern_result.scalar() or 0
        modern_codec_pct = round(modern_count / total * 100, 1)

        # Appropriate bitrates (within 2x of reference for resolution)
        # Simplified: count items with bitrate not null and within reasonable range
        bitrate_ok_result = await self.session.execute(
            select(func.count()).select_from(MediaItem)
            .where(
                MediaItem.video_bitrate.isnot(None),
                MediaItem.video_bitrate > 500_000,
                MediaItem.video_bitrate < 100_000_000,
            )
        )
        bitrate_ok = bitrate_ok_result.scalar() or 0
        has_bitrate_result = await self.session.execute(
            select(func.count()).select_from(MediaItem)
            .where(MediaItem.video_bitrate.isnot(None))
        )
        has_bitrate = has_bitrate_result.scalar() or 1
        bitrate_pct = round(bitrate_ok / max(has_bitrate, 1) * 100, 1)

        # Modern containers (mkv, mp4)
        container_result = await self.session.execute(
            select(func.count()).select_from(MediaItem)
            .where(MediaItem.container.in_(["mkv", "mp4", "m4v"]))
        )
        modern_container = container_result.scalar() or 0
        container_pct = round(modern_container / total * 100, 1)

        # Audio: not lossless bloat (items WITHOUT lossless high-channel audio)
        lossless_codecs = ["truehd", "dts-hd ma", "dts-hd", "pcm", "flac"]
        lossless_result = await self.session.execute(
            select(func.count()).select_from(MediaItem)
            .where(
                MediaItem.audio_codec.in_(lossless_codecs),
                MediaItem.audio_channels >= 6,
            )
        )
        lossless_count = lossless_result.scalar() or 0
        audio_pct = round((total - lossless_count) / total * 100, 1)

        # Weighted score
        score = int(
            modern_codec_pct * 0.40 +
            bitrate_pct * 0.30 +
            container_pct * 0.15 +
            audio_pct * 0.15
        )
        score = max(0, min(100, score))

        # Grade
        if score >= 90: grade = "A"
        elif score >= 75: grade = "B"
        elif score >= 60: grade = "C"
        elif score >= 40: grade = "D"
        else: grade = "F"

        return HealthScoreResponse(
            score=score, modern_codec_pct=modern_codec_pct,
            bitrate_pct=bitrate_pct, container_pct=container_pct,
            audio_pct=audio_pct, grade=grade,
        )

    async def get_trend_sparkline(self, metric: str, days: int = 30) -> List[Dict[str, Any]]:
        """Return daily data points for a sparkline chart."""
        since = datetime.utcnow() - timedelta(days=days)

        if metric == "storage_saved":
            result = await self.session.execute(
                select(
                    func.date(JobLog.created_at).label("day"),
                    func.sum(JobLog.source_size - JobLog.target_size).label("value"),
                )
                .where(JobLog.status == "completed", JobLog.target_size.isnot(None),
                       JobLog.created_at >= since)
                .group_by(func.date(JobLog.created_at))
                .order_by(func.date(JobLog.created_at).asc())
            )
        elif metric == "jobs_completed":
            result = await self.session.execute(
                select(
                    func.date(JobLog.created_at).label("day"),
                    func.count().label("value"),
                )
                .where(JobLog.status == "completed", JobLog.created_at >= since)
                .group_by(func.date(JobLog.created_at))
                .order_by(func.date(JobLog.created_at).asc())
            )
        elif metric == "items_added":
            result = await self.session.execute(
                select(
                    func.date(MediaItem.created_at).label("day"),
                    func.count().label("value"),
                )
                .where(MediaItem.created_at >= since)
                .group_by(func.date(MediaItem.created_at))
                .order_by(func.date(MediaItem.created_at).asc())
            )
        else:
            return []

        rows = result.all()
        cumulative = 0
        points = []
        for day, value in rows:
            val = max(int(value or 0), 0)
            cumulative += val
            points.append({"date": str(day), "value": cumulative})
        return points

    async def get_storage_timeline(self, days: int = 90) -> List[Dict[str, Any]]:
        """Return cumulative library size vs would-be size over time."""
        since = datetime.utcnow() - timedelta(days=days)

        # Get total library size as baseline
        total_result = await self.session.execute(
            select(func.sum(MediaItem.file_size))
        )
        current_total = total_result.scalar() or 0

        # Get daily savings (cumulative)
        result = await self.session.execute(
            select(
                func.date(JobLog.created_at).label("day"),
                func.sum(JobLog.source_size - JobLog.target_size).label("day_savings"),
            )
            .where(JobLog.status == "completed", JobLog.target_size.isnot(None),
                   JobLog.created_at >= since)
            .group_by(func.date(JobLog.created_at))
            .order_by(func.date(JobLog.created_at).asc())
        )
        rows = result.all()

        # Total savings up to the start of our window
        pre_result = await self.session.execute(
            select(func.sum(JobLog.source_size - JobLog.target_size))
            .where(JobLog.status == "completed", JobLog.target_size.isnot(None),
                   JobLog.created_at < since)
        )
        pre_savings = max(int(pre_result.scalar() or 0), 0)

        points = []
        cumulative_savings = pre_savings
        for day, day_savings in rows:
            savings = max(int(day_savings or 0), 0)
            cumulative_savings += savings
            # actual_size = current library size
            # without_transcoding = actual + all savings to date
            points.append({
                "date": str(day),
                "actual_size": current_total,
                "without_transcoding": current_total + cumulative_savings,
                "savings": cumulative_savings,
            })
        return points

    async def get_top_opportunities(self) -> List[SavingsOpportunity]:
        """Top 10 largest untranscoded files with estimated savings."""
        # Get IDs of items that already have completed jobs
        transcoded_subq = select(TranscodeJob.media_item_id).where(
            TranscodeJob.status == "completed",
            TranscodeJob.media_item_id.isnot(None),
        ).distinct()

        result = await self.session.execute(
            select(MediaItem)
            .where(
                MediaItem.video_codec.in_(["h264", "mpeg4", "vc1", "wmv3", "mpeg2video"]),
                MediaItem.id.notin_(transcoded_subq),
            )
            .order_by(MediaItem.file_size.desc())
            .limit(10)
        )
        items = result.scalars().all()

        opportunities = []
        for item in items:
            file_size = item.file_size or 0
            estimated_savings = int(file_size * 0.45)  # Conservative estimate
            opportunities.append(SavingsOpportunity(
                media_item_id=item.id,
                title=item.title or "Unknown",
                file_size=file_size,
                estimated_savings=estimated_savings,
                current_codec=item.video_codec,
                recommended_codec="hevc",
            ))
        return opportunities
