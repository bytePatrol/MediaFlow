import logging
from typing import Optional, List, Dict, Any

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, delete

from app.models.media_item import MediaItem
from app.models.recommendation import Recommendation
from app.models.transcode_job import TranscodeJob
from app.schemas.recommendation import RecommendationResponse, RecommendationSummary, BatchQueueRequest

logger = logging.getLogger(__name__)


class RecommendationService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def get_recommendations(self, type: Optional[str] = None,
                                   include_dismissed: bool = False) -> List[RecommendationResponse]:
        query = select(Recommendation)
        if type:
            query = query.where(Recommendation.type == type)
        if not include_dismissed:
            query = query.where(Recommendation.is_dismissed == False)
        query = query.order_by(Recommendation.created_at.desc())
        result = await self.session.execute(query)
        recs = result.scalars().all()

        responses = []
        for rec in recs:
            resp = RecommendationResponse.model_validate(rec)
            if rec.media_item_id:
                media_result = await self.session.execute(
                    select(MediaItem.title, MediaItem.file_size)
                    .where(MediaItem.id == rec.media_item_id)
                )
                row = media_result.first()
                if row:
                    resp.media_title = row[0]
                    resp.media_file_size = row[1]
            responses.append(resp)
        return responses

    async def get_summary(self) -> RecommendationSummary:
        total_result = await self.session.execute(
            select(func.count()).select_from(Recommendation)
        )
        total = total_result.scalar() or 0

        type_result = await self.session.execute(
            select(Recommendation.type, func.count()).group_by(Recommendation.type)
        )
        by_type = {t: c for t, c in type_result.all()}

        savings_result = await self.session.execute(
            select(func.sum(Recommendation.estimated_savings))
            .where(Recommendation.is_dismissed == False)
        )
        total_savings = savings_result.scalar() or 0

        dismissed_result = await self.session.execute(
            select(func.count()).select_from(Recommendation)
            .where(Recommendation.is_dismissed == True)
        )
        dismissed = dismissed_result.scalar() or 0

        actioned_result = await self.session.execute(
            select(func.count()).select_from(Recommendation)
            .where(Recommendation.is_actioned == True)
        )
        actioned = actioned_result.scalar() or 0

        return RecommendationSummary(
            total=total, by_type=by_type, total_estimated_savings=total_savings,
            dismissed_count=dismissed, actioned_count=actioned,
        )

    async def run_full_analysis(self) -> int:
        await self.session.execute(
            delete(Recommendation).where(Recommendation.is_actioned == False, Recommendation.is_dismissed == False)
        )
        await self.session.commit()

        count = 0
        count += await self._analyze_codec_modernization()
        count += await self._analyze_quality_overkill()
        count += await self._detect_duplicates()
        count += await self._analyze_quality_gaps()
        count += await self._analyze_storage_optimization()
        await self.session.commit()
        return count

    async def _analyze_codec_modernization(self) -> int:
        result = await self.session.execute(
            select(MediaItem).where(
                MediaItem.video_codec.in_(["h264", "mpeg4", "vc1", "wmv3"])
            )
        )
        items = result.scalars().all()
        count = 0
        for item in items:
            savings = int((item.file_size or 0) * 0.5)
            rec = Recommendation(
                media_item_id=item.id,
                type="codec_upgrade",
                severity="warning" if (item.file_size or 0) > 10_000_000_000 else "info",
                title=f"Upgrade {item.title} from {item.video_codec} to HEVC",
                description=f"Converting from {item.video_codec} to HEVC could save approximately {savings // 1_000_000_000:.1f} GB with minimal quality loss.",
                estimated_savings=savings,
            )
            self.session.add(rec)
            count += 1
        return count

    async def _analyze_quality_overkill(self) -> int:
        result = await self.session.execute(
            select(MediaItem).where(
                MediaItem.resolution_tier == "4K",
                MediaItem.is_hdr == True,
                MediaItem.play_count < 2,
                MediaItem.file_size > 30_000_000_000,
            )
        )
        items = result.scalars().all()
        count = 0
        for item in items:
            savings = int((item.file_size or 0) * 0.6)
            rec = Recommendation(
                media_item_id=item.id,
                type="quality_overkill",
                severity="info",
                title=f"{item.title} - 4K HDR with low play count",
                description=f"This 4K HDR file is {(item.file_size or 0) / 1_000_000_000:.1f} GB but has only been played {item.play_count} times. Consider downscaling to 1080p.",
                estimated_savings=savings,
            )
            self.session.add(rec)
            count += 1
        return count

    async def _detect_duplicates(self) -> int:
        result = await self.session.execute(
            select(MediaItem.title, MediaItem.year, func.count())
            .group_by(MediaItem.title, MediaItem.year)
            .having(func.count() > 1)
        )
        duplicates = result.all()
        count = 0
        for title, year, dup_count in duplicates:
            items_result = await self.session.execute(
                select(MediaItem).where(
                    MediaItem.title == title,
                    MediaItem.year == year,
                ).order_by(MediaItem.file_size.desc())
            )
            items = items_result.scalars().all()
            if len(items) > 1:
                smallest = items[-1]
                savings = sum(i.file_size or 0 for i in items[1:])
                rec = Recommendation(
                    media_item_id=items[0].id,
                    type="duplicate",
                    severity="warning",
                    title=f"Duplicate detected: {title} ({year})",
                    description=f"Found {dup_count} copies of this title. Removing duplicates could save {savings / 1_000_000_000:.1f} GB.",
                    estimated_savings=savings,
                )
                self.session.add(rec)
                count += 1
        return count

    async def _analyze_quality_gaps(self) -> int:
        avg_result = await self.session.execute(
            select(func.avg(MediaItem.video_bitrate))
        )
        avg_bitrate = avg_result.scalar() or 0

        result = await self.session.execute(
            select(MediaItem).where(
                MediaItem.video_bitrate < avg_bitrate * 0.4,
                MediaItem.video_bitrate.isnot(None),
            )
        )
        items = result.scalars().all()
        count = 0
        for item in items:
            rec = Recommendation(
                media_item_id=item.id,
                type="low_quality",
                severity="info",
                title=f"{item.title} - Below average quality",
                description=f"Bitrate ({item.video_bitrate} bps) is significantly below library average ({int(avg_bitrate)} bps). Consider finding a higher quality source.",
                estimated_savings=0,
            )
            self.session.add(rec)
            count += 1
        return count

    async def _analyze_storage_optimization(self) -> int:
        result = await self.session.execute(
            select(MediaItem)
            .where(MediaItem.file_size > 20_000_000_000)
            .order_by((MediaItem.file_size / func.max(MediaItem.play_count, 1)).desc())
            .limit(20)
        )
        items = result.scalars().all()
        count = 0
        for item in items:
            savings = int((item.file_size or 0) * 0.4)
            rec = Recommendation(
                media_item_id=item.id,
                type="storage_optimization",
                severity="info",
                title=f"{item.title} - High storage, low engagement",
                description=f"This file uses {(item.file_size or 0) / 1_000_000_000:.1f} GB but has only {item.play_count} plays. Compression could save {savings / 1_000_000_000:.1f} GB.",
                estimated_savings=savings,
            )
            self.session.add(rec)
            count += 1
        return count

    async def batch_queue(self, request: BatchQueueRequest) -> Dict[str, Any]:
        from app.services.transcode_service import TranscodeService
        from app.schemas.transcode import TranscodeJobCreate

        result = await self.session.execute(
            select(Recommendation).where(Recommendation.id.in_(request.recommendation_ids))
        )
        recs = result.scalars().all()

        media_ids = []
        preset_id = request.preset_id
        for rec in recs:
            if rec.media_item_id:
                media_ids.append(rec.media_item_id)
                if not preset_id and rec.suggested_preset_id:
                    preset_id = rec.suggested_preset_id
                rec.is_actioned = True

        # Fall back to the first available preset (Balanced) if none specified
        if not preset_id:
            from app.models.transcode_preset import TranscodePreset
            default_result = await self.session.execute(
                select(TranscodePreset).order_by(TranscodePreset.id.asc()).limit(1)
            )
            default_preset = default_result.scalar_one_or_none()
            if default_preset:
                preset_id = default_preset.id

        if not media_ids:
            await self.session.commit()
            return {"status": "queued", "jobs_created": 0}

        transcode_service = TranscodeService(self.session)
        create_request = TranscodeJobCreate(
            media_item_ids=media_ids,
            preset_id=preset_id,
        )
        jobs = await transcode_service.create_jobs(create_request)

        return {"status": "queued", "jobs_created": len(jobs)}
