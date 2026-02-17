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

    async def get_library_health(self):
        """Per-library health report with scores and grades."""
        from app.models.plex_library import PlexLibrary
        from app.models.recommendation import Recommendation

        result = await self.session.execute(
            select(PlexLibrary).order_by(PlexLibrary.title)
        )
        libraries = result.scalars().all()

        cards = []
        total_potential = 0
        total_score = 0

        for lib in libraries:
            items_result = await self.session.execute(
                select(
                    func.count(),
                    func.sum(MediaItem.file_size),
                    func.avg(MediaItem.video_bitrate),
                ).where(MediaItem.plex_library_id == lib.id)
            )
            row = items_result.first()
            total_items = row[0] or 0
            total_size = row[1] or 0
            avg_bitrate = row[2] or 0

            if total_items == 0:
                continue

            # Codec distribution
            codec_result = await self.session.execute(
                select(MediaItem.video_codec, func.count())
                .where(MediaItem.plex_library_id == lib.id, MediaItem.video_codec.isnot(None))
                .group_by(MediaItem.video_codec)
            )
            codec_dist = {c: n for c, n in codec_result.all()}

            # Resolution distribution
            res_result = await self.session.execute(
                select(MediaItem.resolution_tier, func.count())
                .where(MediaItem.plex_library_id == lib.id, MediaItem.resolution_tier.isnot(None))
                .group_by(MediaItem.resolution_tier)
            )
            res_dist = {r: n for r, n in res_result.all()}

            # HDR count
            hdr_result = await self.session.execute(
                select(func.count()).select_from(MediaItem)
                .where(MediaItem.plex_library_id == lib.id, MediaItem.is_hdr == True)
            )
            hdr_count = hdr_result.scalar() or 0

            # Modern codec percentage
            modern_codecs = {"hevc", "h265", "av1"}
            modern_count = sum(v for k, v in codec_dist.items() if k and k.lower() in modern_codecs)
            optimization_pct = (modern_count / total_items * 100) if total_items > 0 else 0

            # Potential savings from recommendations
            savings_result = await self.session.execute(
                select(func.sum(Recommendation.estimated_savings))
                .join(MediaItem, Recommendation.media_item_id == MediaItem.id)
                .where(
                    MediaItem.plex_library_id == lib.id,
                    Recommendation.is_dismissed == False,
                    Recommendation.is_actioned == False,
                )
            )
            potential_savings = savings_result.scalar() or 0
            total_potential += potential_savings

            # Health score calculation
            score = 0
            score += min(40, int(optimization_pct * 0.4))  # Up to 40 for modern codecs

            # Container score (modern = mkv, mp4)
            container_result = await self.session.execute(
                select(func.count()).select_from(MediaItem)
                .where(
                    MediaItem.plex_library_id == lib.id,
                    MediaItem.container.in_(["mkv", "mp4", "m4v"]),
                )
            )
            modern_containers = container_result.scalar() or 0
            container_pct = (modern_containers / total_items * 100) if total_items > 0 else 0
            score += min(20, int(container_pct * 0.2))  # Up to 20

            # Bitrate efficiency score
            score += min(20, 20 if avg_bitrate > 0 else 0)  # 20 if we have bitrate data

            # No duplicates bonus
            score += 10  # Simplified

            # Low quality penalty
            low_q_result = await self.session.execute(
                select(func.count()).select_from(Recommendation)
                .join(MediaItem, Recommendation.media_item_id == MediaItem.id)
                .where(
                    MediaItem.plex_library_id == lib.id,
                    Recommendation.type == "low_quality",
                )
            )
            low_quality = low_q_result.scalar() or 0
            if low_quality > total_items * 0.1:
                score -= 10

            score = max(0, min(100, score))
            total_score += score

            grade = "A" if score >= 90 else "B" if score >= 75 else "C" if score >= 60 else "D" if score >= 40 else "F"

            cards.append({
                "library_id": lib.id,
                "library_title": lib.title,
                "total_items": total_items,
                "total_size": total_size,
                "codec_distribution": codec_dist,
                "resolution_distribution": res_dist,
                "optimization_pct": round(optimization_pct, 1),
                "health_score": score,
                "health_grade": grade,
                "potential_savings": potential_savings,
                "avg_bitrate": round(avg_bitrate, 0),
                "hdr_count": hdr_count,
            })

        overall_score = int(total_score / len(cards)) if cards else 0
        overall_grade = "A" if overall_score >= 90 else "B" if overall_score >= 75 else "C" if overall_score >= 60 else "D" if overall_score >= 40 else "F"

        return {
            "libraries": cards,
            "overall_score": overall_score,
            "overall_grade": overall_grade,
            "total_potential_savings": total_potential,
        }

    async def get_codec_migration(self, library_id=None):
        """Codec migration progress with historical snapshots."""
        from app.models.codec_migration_snapshot import CodecMigrationSnapshot

        # Current distribution
        query = select(MediaItem.video_codec, func.count())
        if library_id:
            query = query.where(MediaItem.plex_library_id == library_id)
        query = query.where(MediaItem.video_codec.isnot(None)).group_by(MediaItem.video_codec)
        result = await self.session.execute(query)
        current = {c: n for c, n in result.all()}

        total = sum(current.values())
        current_pct = {c: round(n / total * 100, 1) if total > 0 else 0 for c, n in current.items()}

        modern_codecs = {"hevc", "h265", "av1"}
        modern_count = sum(v for k, v in current.items() if k and k.lower() in modern_codecs)
        modern_pct = round(modern_count / total * 100, 1) if total > 0 else 0

        # Save snapshot
        import json
        snapshot = CodecMigrationSnapshot(
            library_id=library_id,
            codec_distribution_json=json.dumps(current),
            total_items=total,
            modern_codec_pct=modern_pct,
        )
        self.session.add(snapshot)
        await self.session.commit()

        # Historical data
        hist_query = (
            select(CodecMigrationSnapshot)
            .order_by(CodecMigrationSnapshot.snapshot_date.desc())
            .limit(90)
        )
        if library_id:
            hist_query = hist_query.where(CodecMigrationSnapshot.library_id == library_id)
        else:
            hist_query = hist_query.where(CodecMigrationSnapshot.library_id.is_(None))

        hist_result = await self.session.execute(hist_query)
        snapshots = hist_result.scalars().all()

        history = []
        for s in reversed(snapshots):
            try:
                dist = json.loads(s.codec_distribution_json) if s.codec_distribution_json else {}
            except Exception:
                dist = {}
            history.append({
                "date": s.snapshot_date.isoformat() if s.snapshot_date else "",
                "codec_distribution": dist,
                "total_items": s.total_items,
                "modern_codec_pct": s.modern_codec_pct,
            })

        return {
            "current": current,
            "current_pct": current_pct,
            "history": history,
            "total_items": total,
            "modern_pct": modern_pct,
            "library_id": library_id,
        }

    async def get_cost_analytics(self):
        """Cloud cost analytics with trends and projections."""
        from app.models.cloud_cost import CloudCostRecord
        from datetime import datetime, timedelta

        # Total cloud costs
        cost_result = await self.session.execute(
            select(
                func.count(),
                func.sum(CloudCostRecord.cost_usd),
            ).where(CloudCostRecord.record_type == "job")
        )
        row = cost_result.first()
        total_jobs_cloud = row[0] or 0
        total_cloud_cost = row[1] or 0

        # Total savings from cloud jobs
        cloud_savings_result = await self.session.execute(
            select(func.sum(JobLog.source_size - JobLog.target_size))
            .where(
                JobLog.status == "completed",
                JobLog.compute_cost.isnot(None),
                JobLog.compute_cost > 0,
                JobLog.target_size.isnot(None),
            )
        )
        cloud_savings = cloud_savings_result.scalar() or 0
        cloud_savings_gb = cloud_savings / 1_000_000_000 if cloud_savings > 0 else 0
        cost_per_gb = total_cloud_cost / cloud_savings_gb if cloud_savings_gb > 0 else 0

        # Local savings
        local_savings_result = await self.session.execute(
            select(func.sum(JobLog.source_size - JobLog.target_size))
            .where(
                JobLog.status == "completed",
                JobLog.target_size.isnot(None),
                (JobLog.compute_cost.is_(None)) | (JobLog.compute_cost == 0),
            )
        )
        local_savings = local_savings_result.scalar() or 0

        # Estimate local cost (assume $0.10/hr for electricity)
        local_time_result = await self.session.execute(
            select(func.sum(JobLog.duration_seconds))
            .where(
                JobLog.status == "completed",
                (JobLog.compute_cost.is_(None)) | (JobLog.compute_cost == 0),
            )
        )
        local_time = local_time_result.scalar() or 0
        local_estimated_cost = (local_time / 3600) * 0.10

        # Monthly trend
        monthly_trend = []
        for i in range(5, -1, -1):
            month_start = datetime.utcnow().replace(day=1) - timedelta(days=i * 30)
            month_end = month_start + timedelta(days=30)
            month_result = await self.session.execute(
                select(func.count(), func.sum(CloudCostRecord.cost_usd))
                .where(
                    CloudCostRecord.record_type == "job",
                    CloudCostRecord.start_time >= month_start,
                    CloudCostRecord.start_time < month_end,
                )
            )
            mrow = month_result.first()
            monthly_trend.append({
                "month": month_start.strftime("%Y-%m"),
                "cost": round(mrow[1] or 0, 2),
                "jobs": mrow[0] or 0,
            })

        # Projection based on last 3 months average
        recent_costs = [m["cost"] for m in monthly_trend[-3:] if m["cost"] > 0]
        monthly_projection = round(sum(recent_costs) / len(recent_costs), 2) if recent_costs else 0

        return {
            "total_cloud_cost": round(total_cloud_cost, 2),
            "total_jobs_cloud": total_jobs_cloud,
            "cost_per_gb_saved": round(cost_per_gb, 4),
            "cloud_vs_local": {
                "cloud_cost": round(total_cloud_cost, 2),
                "local_estimated_cost": round(local_estimated_cost, 2),
                "savings": round(local_estimated_cost - total_cloud_cost, 2),
            },
            "monthly_trend": monthly_trend,
            "monthly_projection": monthly_projection,
        }

    async def get_worker_heatmap(self, days=30):
        """Worker performance heatmap by hour of day."""
        from datetime import datetime, timedelta

        cutoff = datetime.utcnow() - timedelta(days=days)

        # Get all workers
        workers_result = await self.session.execute(
            select(WorkerServer.id, WorkerServer.name)
        )
        workers = [{"id": w[0], "name": w[1]} for w in workers_result.all()]

        entries = []
        for worker in workers:
            for hour in range(24):
                hour_result = await self.session.execute(
                    select(
                        func.count(),
                        func.avg(JobLog.avg_fps),
                        func.sum(JobLog.duration_seconds),
                    ).where(
                        JobLog.worker_server_id == worker["id"],
                        JobLog.created_at >= cutoff,
                        func.strftime("%H", JobLog.created_at) == f"{hour:02d}",
                    )
                )
                row = hour_result.first()
                job_count = row[0] or 0
                avg_fps = row[1] or 0
                total_time = row[2] or 0
                utilization = min(1.0, total_time / (days * 3600)) if days > 0 else 0

                entries.append({
                    "worker_id": worker["id"],
                    "worker_name": worker["name"],
                    "hour": hour,
                    "avg_fps": round(avg_fps, 1),
                    "job_count": job_count,
                    "utilization": round(utilization, 3),
                })

        return {"entries": entries, "workers": workers}

    async def get_job_timeline(self, days=7):
        """Job timeline for Gantt view."""
        from datetime import datetime, timedelta

        cutoff = datetime.utcnow() - timedelta(days=days)

        result = await self.session.execute(
            select(
                TranscodeJob.id,
                TranscodeJob.status,
                TranscodeJob.started_at,
                TranscodeJob.completed_at,
                TranscodeJob.worker_server_id,
                MediaItem.title,
                WorkerServer.name,
                JobLog.source_codec,
                JobLog.target_codec,
                JobLog.duration_seconds,
            )
            .outerjoin(MediaItem, TranscodeJob.media_item_id == MediaItem.id)
            .outerjoin(WorkerServer, TranscodeJob.worker_server_id == WorkerServer.id)
            .outerjoin(JobLog, TranscodeJob.id == JobLog.job_id)
            .where(TranscodeJob.created_at >= cutoff)
            .order_by(TranscodeJob.started_at.desc().nullslast())
            .limit(200)
        )
        rows = result.all()

        jobs = []
        for r in rows:
            jobs.append({
                "job_id": r[0],
                "status": r[1],
                "started_at": r[2].isoformat() if r[2] else None,
                "completed_at": r[3].isoformat() if r[3] else None,
                "worker_id": r[4],
                "title": r[5] or f"Job #{r[0]}",
                "worker_name": r[6],
                "source_codec": r[7],
                "target_codec": r[8],
                "duration_seconds": r[9],
            })

        workers_result = await self.session.execute(
            select(WorkerServer.id, WorkerServer.name)
        )
        workers = [{"id": w[0], "name": w[1]} for w in workers_result.all()]

        return {"jobs": jobs, "workers": workers}

    async def get_codec_strategy(self):
        """Codec strategy advisor based on job history."""
        from app.models.plex_library import PlexLibrary

        libraries_result = await self.session.execute(
            select(PlexLibrary).order_by(PlexLibrary.title)
        )
        libraries = libraries_result.scalars().all()

        advice = []
        for lib in libraries:
            # Get dominant codec
            codec_result = await self.session.execute(
                select(MediaItem.video_codec, func.count())
                .where(MediaItem.plex_library_id == lib.id, MediaItem.video_codec.isnot(None))
                .group_by(MediaItem.video_codec)
                .order_by(func.count().desc())
                .limit(1)
            )
            dominant_row = codec_result.first()
            if not dominant_row:
                continue
            dominant_codec = dominant_row[0]

            # Check job history for this library
            savings_result = await self.session.execute(
                select(
                    JobLog.target_codec,
                    func.count(),
                    func.avg(JobLog.size_reduction),
                    func.sum(JobLog.source_size),
                    func.sum(JobLog.target_size),
                )
                .join(TranscodeJob, JobLog.job_id == TranscodeJob.id)
                .join(MediaItem, TranscodeJob.media_item_id == MediaItem.id)
                .where(
                    MediaItem.plex_library_id == lib.id,
                    JobLog.status == "completed",
                    JobLog.target_codec.isnot(None),
                )
                .group_by(JobLog.target_codec)
            )
            codec_savings = savings_result.all()

            best_target = "hevc"
            best_savings = 0
            total_projected = 0

            for target_codec, count, avg_reduction, total_src, total_tgt in codec_savings:
                savings_pct = ((total_src or 0) - (total_tgt or 0)) / (total_src or 1) * 100
                if savings_pct > best_savings:
                    best_savings = savings_pct
                    best_target = target_codec

            # Project total savings if all non-modern items were transcoded
            non_modern_result = await self.session.execute(
                select(func.sum(MediaItem.file_size))
                .where(
                    MediaItem.plex_library_id == lib.id,
                    ~MediaItem.video_codec.in_(["hevc", "h265", "av1"]),
                )
            )
            non_modern_size = non_modern_result.scalar() or 0
            total_projected = int(non_modern_size * (best_savings / 100)) if best_savings > 0 else int(non_modern_size * 0.4)

            rationale = f"Based on {sum(r[1] for r in codec_savings)} completed jobs, {best_target.upper()} achieves {best_savings:.0f}% savings" if codec_savings else f"Recommend HEVC as default target (estimated 40% savings)"

            advice.append({
                "library_id": lib.id,
                "library_title": lib.title,
                "current_dominant_codec": dominant_codec,
                "recommended_target": best_target,
                "avg_savings_pct": round(best_savings, 1),
                "total_projected_savings": total_projected,
                "rationale": rationale,
            })

        # Per-resolution recommendations
        res_recs = []
        for res in ["4K", "1080p", "720p", "480p"]:
            res_result = await self.session.execute(
                select(
                    JobLog.target_codec,
                    func.avg(JobLog.size_reduction),
                    func.count(),
                )
                .where(
                    JobLog.status == "completed",
                    JobLog.source_resolution == res,
                    JobLog.target_codec.isnot(None),
                )
                .group_by(JobLog.target_codec)
                .order_by(func.avg(JobLog.size_reduction).desc())
                .limit(1)
            )
            best = res_result.first()
            if best:
                res_recs.append({
                    "resolution": res,
                    "best_codec": best[0],
                    "avg_savings": round((best[1] or 0) * 100, 1),
                    "sample_size": best[2],
                })

        return {"advice": advice, "resolution_recommendations": res_recs}

    async def get_storage_projection(self):
        """Enhanced storage projection with confidence bands."""
        from datetime import datetime, timedelta

        # Current total size
        size_result = await self.session.execute(select(func.sum(MediaItem.file_size)))
        current_total = size_result.scalar() or 0

        # Total potential savings from recommendations
        from app.models.recommendation import Recommendation
        savings_result = await self.session.execute(
            select(func.sum(Recommendation.estimated_savings))
            .where(
                Recommendation.is_dismissed == False,
                Recommendation.is_actioned == False,
            )
        )
        potential_savings = savings_result.scalar() or 0

        # Monthly savings rate (from last 3 months of completed jobs)
        three_months_ago = datetime.utcnow() - timedelta(days=90)
        monthly_result = await self.session.execute(
            select(func.sum(JobLog.source_size - JobLog.target_size))
            .where(
                JobLog.status == "completed",
                JobLog.target_size.isnot(None),
                JobLog.created_at >= three_months_ago,
            )
        )
        total_saved_3m = monthly_result.scalar() or 0
        monthly_pace = int(total_saved_3m / 3)

        # Confidence bands for 12 months
        confidence_bands = []
        for i in range(1, 13):
            month_date = datetime.utcnow() + timedelta(days=i * 30)
            mid = monthly_pace * i
            low = int(mid * 0.6)
            high = int(mid * 1.5)
            confidence_bands.append({
                "month": month_date.strftime("%Y-%m"),
                "low": low,
                "mid": mid,
                "high": high,
            })

        return {
            "current_total_size": current_total,
            "if_all_optimized": current_total - potential_savings,
            "potential_savings": potential_savings,
            "current_pace_monthly": monthly_pace,
            "months_to_storage_limit": None,
            "confidence_bands": confidence_bands,
        }
