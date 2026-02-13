import logging
import math
from datetime import datetime
from typing import Optional, List, Dict, Any, Tuple

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func, delete

from app.models.media_item import MediaItem
from app.models.recommendation import Recommendation, AnalysisRun
from app.models.transcode_job import TranscodeJob
from app.models.job_log import JobLog
from app.models.app_settings import AppSetting
from app.schemas.recommendation import RecommendationResponse, RecommendationSummary, BatchQueueRequest

logger = logging.getLogger(__name__)

# Codec generation ordering (older = higher score)
CODEC_AGE = {
    "mpeg1video": 6, "mpeg2video": 5, "mpeg4": 4, "wmv3": 4, "vc1": 3,
    "h264": 2, "hevc": 1, "h265": 1, "av1": 0,
}

# Default fixed compression ratios (source → hevc) when no learned data
DEFAULT_RATIOS = {
    ("mpeg2video", "hevc"): 0.30,
    ("mpeg4", "hevc"): 0.40,
    ("wmv3", "hevc"): 0.40,
    ("vc1", "hevc"): 0.45,
    ("h264", "hevc"): 0.55,
    ("h264", "av1"): 0.50,
    ("hevc", "av1"): 0.80,
}

# Known-good bitrates per resolution (bps) for HEVC
REFERENCE_BITRATES = {
    "4K": 15_000_000,
    "1080p": 5_000_000,
    "720p": 2_500_000,
    "480p": 1_000_000,
    "SD": 800_000,
}

# Old containers that should be modernized
OLD_CONTAINERS = {"avi", "wmv", "mpg", "mpeg", "divx", "ogm", "flv", "rm", "rmvb", "asf"}

# Lossless audio codecs that can be downmixed for savings
LOSSLESS_AUDIO = {"truehd", "dts-hd ma", "dts-hd", "dtshd", "pcm", "flac", "dts ma", "dts-hd.ma"}

# Codecs eligible for upgrade
UPGRADE_CODECS = {"h264", "mpeg4", "vc1", "wmv3", "mpeg2video", "mpeg1video"}


class RecommendationService:
    def __init__(self, session: AsyncSession):
        self.session = session

    # ── Public API ──────────────────────────────────────────────────────

    async def get_recommendations(self, type: Optional[str] = None,
                                   include_dismissed: bool = False) -> List[RecommendationResponse]:
        query = select(Recommendation)
        if type:
            query = query.where(Recommendation.type == type)
        if not include_dismissed:
            query = query.where(Recommendation.is_dismissed == False)  # noqa: E712
        query = query.order_by(Recommendation.priority_score.desc().nullslast(), Recommendation.created_at.desc())
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
            .where(Recommendation.is_dismissed == False)  # noqa: E712
        )
        total_savings = savings_result.scalar() or 0

        dismissed_result = await self.session.execute(
            select(func.count()).select_from(Recommendation)
            .where(Recommendation.is_dismissed == True)  # noqa: E712
        )
        dismissed = dismissed_result.scalar() or 0

        actioned_result = await self.session.execute(
            select(func.count()).select_from(Recommendation)
            .where(Recommendation.is_actioned == True)  # noqa: E712
        )
        actioned = actioned_result.scalar() or 0

        return RecommendationSummary(
            total=total, by_type=by_type, total_estimated_savings=total_savings,
            dismissed_count=dismissed, actioned_count=actioned,
        )

    async def run_full_analysis(self, trigger: str = "manual") -> Dict[str, Any]:
        """Run all analyzers and return an analysis run summary."""
        # Create analysis run record
        run = AnalysisRun(trigger=trigger)
        self.session.add(run)
        await self.session.flush()  # get run.id

        # Clear non-dismissed, non-actioned recommendations
        await self.session.execute(
            delete(Recommendation).where(
                Recommendation.is_actioned == False,  # noqa: E712
                Recommendation.is_dismissed == False,  # noqa: E712
            )
        )
        await self.session.commit()

        # Load configurable thresholds
        thresholds = await self._load_thresholds()

        # Load learned compression ratios from job history
        learned_ratios = await self._get_learned_ratios()

        # Count total items for the run
        count_result = await self.session.execute(select(func.count()).select_from(MediaItem))
        total_items = count_result.scalar() or 0

        # Run all analyzers
        all_recs: List[Recommendation] = []
        all_recs.extend(await self._analyze_codec_modernization(thresholds, learned_ratios))
        all_recs.extend(await self._analyze_quality_overkill(thresholds, learned_ratios))
        all_recs.extend(await self._detect_duplicates())
        all_recs.extend(await self._analyze_quality_gaps(thresholds))
        all_recs.extend(await self._analyze_storage_optimization(thresholds, learned_ratios))
        all_recs.extend(await self._analyze_audio_optimization(thresholds))
        all_recs.extend(await self._analyze_container_modernize(thresholds))
        all_recs.extend(await self._analyze_hdr_to_sdr(thresholds, learned_ratios))
        all_recs.extend(await self._analyze_batch_similar(thresholds, learned_ratios))

        # Score and attach to run
        for rec in all_recs:
            rec.analysis_run_id = run.id
            self.session.add(rec)

        await self.session.flush()

        # Update run with completion stats
        total_savings = sum(r.estimated_savings or 0 for r in all_recs)
        run.completed_at = datetime.utcnow()
        run.total_items_analyzed = total_items
        run.recommendations_generated = len(all_recs)
        run.total_estimated_savings = total_savings
        await self.session.commit()

        # Fire notification
        try:
            from app.utils.notify import fire_notification
            await fire_notification("analysis.completed", {
                "run_id": run.id,
                "recommendations_generated": len(all_recs),
                "total_estimated_savings": total_savings,
            })
        except Exception:
            pass

        return {
            "run_id": run.id,
            "trigger": trigger,
            "total_items_analyzed": total_items,
            "recommendations_generated": len(all_recs),
            "total_estimated_savings": total_savings,
        }

    async def get_analysis_history(self, limit: int = 20) -> List[Dict[str, Any]]:
        result = await self.session.execute(
            select(AnalysisRun).order_by(AnalysisRun.id.desc()).limit(limit)
        )
        runs = result.scalars().all()
        return [
            {
                "id": r.id,
                "started_at": r.started_at.isoformat() if r.started_at else None,
                "completed_at": r.completed_at.isoformat() if r.completed_at else None,
                "total_items_analyzed": r.total_items_analyzed,
                "recommendations_generated": r.recommendations_generated,
                "total_estimated_savings": r.total_estimated_savings,
                "trigger": r.trigger,
            }
            for r in runs
        ]

    async def get_savings_achieved(self) -> Dict[str, Any]:
        """Calculate actual savings from completed transcode jobs."""
        result = await self.session.execute(
            select(
                func.count(),
                func.sum(JobLog.source_size),
                func.sum(JobLog.target_size),
            ).where(
                JobLog.status == "completed",
                JobLog.source_size.isnot(None),
                JobLog.target_size.isnot(None),
            )
        )
        row = result.first()
        total_jobs = row[0] or 0
        total_original = row[1] or 0
        total_final = row[2] or 0
        total_saved = total_original - total_final

        # Breakdown by codec pair
        codec_result = await self.session.execute(
            select(
                JobLog.source_codec,
                JobLog.target_codec,
                func.count(),
                func.sum(JobLog.source_size),
                func.sum(JobLog.target_size),
            ).where(
                JobLog.status == "completed",
                JobLog.source_codec.isnot(None),
                JobLog.target_codec.isnot(None),
            ).group_by(JobLog.source_codec, JobLog.target_codec)
        )
        by_codec = []
        for src, tgt, cnt, orig, final in codec_result.all():
            by_codec.append({
                "source_codec": src,
                "target_codec": tgt,
                "jobs": cnt,
                "original_size": orig or 0,
                "final_size": final or 0,
                "saved": (orig or 0) - (final or 0),
            })

        return {
            "total_jobs": total_jobs,
            "total_original_size": total_original,
            "total_final_size": total_final,
            "total_saved": total_saved,
            "by_codec": by_codec,
        }

    # ── Configurable Thresholds ─────────────────────────────────────────

    async def _load_thresholds(self) -> Dict[str, Any]:
        """Load intelligence thresholds from app_settings with fallback defaults."""
        defaults = {
            "intel.overkill_min_size_gb": "30",
            "intel.overkill_max_plays": "2",
            "intel.storage_opt_min_size_gb": "20",
            "intel.storage_opt_top_n": "20",
            "intel.audio_channels_threshold": "6",
            "intel.auto_analyze_on_sync": "true",
            "intel.quality_gap_bitrate_pct": "40",
            "intel.hdr_max_plays": "3",
            "intel.batch_min_group_size": "5",
        }
        thresholds = {}
        result = await self.session.execute(
            select(AppSetting).where(AppSetting.key.like("intel.%"))
        )
        settings = {s.key: s.value for s in result.scalars().all()}

        for key, default in defaults.items():
            val = settings.get(key, default)
            short = key.replace("intel.", "")
            if val in ("true", "false"):
                thresholds[short] = val == "true"
            else:
                try:
                    thresholds[short] = int(val) if "." not in str(val) else float(val)
                except (ValueError, TypeError):
                    thresholds[short] = default
        return thresholds

    # ── Learn from Transcode Results ────────────────────────────────────

    async def _get_learned_ratios(self) -> Dict[Tuple[str, str], float]:
        """Query job_logs to learn actual compression ratios per codec pair."""
        result = await self.session.execute(
            select(
                JobLog.source_codec,
                JobLog.target_codec,
                func.count(),
                func.avg(JobLog.target_size * 1.0 / func.nullif(JobLog.source_size, 0)),
            ).where(
                JobLog.status == "completed",
                JobLog.source_codec.isnot(None),
                JobLog.target_codec.isnot(None),
                JobLog.source_size > 0,
                JobLog.target_size.isnot(None),
            ).group_by(JobLog.source_codec, JobLog.target_codec)
        )
        ratios = {}
        for src, tgt, count, avg_ratio in result.all():
            if count >= 3 and avg_ratio is not None:
                ratios[(src.lower(), tgt.lower())] = round(avg_ratio, 3)
        return ratios

    # ── Savings Estimation ──────────────────────────────────────────────

    def _estimate_savings(self, item: MediaItem, target_codec: str,
                          learned_ratios: Dict[Tuple[str, str], float]) -> Tuple[int, float]:
        """Estimate byte savings and confidence for transcoding item to target_codec."""
        source_codec = (item.video_codec or "").lower()
        target = target_codec.lower()
        file_size = item.file_size or 0

        # Check learned ratios first (high confidence)
        key = (source_codec, target)
        if key in learned_ratios:
            ratio = learned_ratios[key]
            savings = int(file_size * (1 - ratio))
            return (max(savings, 0), 0.9)

        # Check default ratios (medium confidence)
        if key in DEFAULT_RATIOS:
            ratio = DEFAULT_RATIOS[key]
            savings = int(file_size * (1 - ratio))
            return (max(savings, 0), 0.5)

        # Bitrate-based estimation (lower confidence)
        resolution = item.resolution_tier or "1080p"
        ref_bitrate = REFERENCE_BITRATES.get(resolution, 5_000_000)
        current_bitrate = item.video_bitrate or 0

        if current_bitrate > ref_bitrate * 1.5:
            # File is significantly over reference — estimate based on bitrate gap
            ratio = ref_bitrate / current_bitrate
            savings = int(file_size * (1 - ratio))
            return (max(savings, 0), 0.3)

        # Fallback: assume 40% savings
        savings = int(file_size * 0.40)
        return (max(savings, 0), 0.2)

    # ── Priority Scoring ────────────────────────────────────────────────

    @staticmethod
    def _score_recommendation(rec: Recommendation, item: Optional[MediaItem]) -> float:
        """Score a recommendation 0-100 for prioritization."""
        score = 0.0

        # Size weight (40%) — log scale, bigger files = higher priority
        if item and item.file_size:
            size_gb = item.file_size / 1_000_000_000
            # 1 GB = ~0, 10 GB = ~40, 100 GB = ~80
            score += min(40.0, math.log10(max(size_gb, 0.1) + 1) * 20)

        # Codec age weight (25%)
        if item and item.video_codec:
            age = CODEC_AGE.get(item.video_codec.lower(), 0)
            score += (age / 6) * 25

        # Confidence weight (20%)
        if rec.confidence:
            score += rec.confidence * 20

        # Play count weight (15%) — more plays = higher value to optimize
        if item and item.play_count:
            score += min(15.0, item.play_count * 1.5)

        return round(min(100.0, score), 1)

    # ── Analyzers ───────────────────────────────────────────────────────

    async def _analyze_codec_modernization(self, thresholds: Dict,
                                            learned_ratios: Dict) -> List[Recommendation]:
        result = await self.session.execute(
            select(MediaItem).where(
                MediaItem.video_codec.in_(list(UPGRADE_CODECS))
            )
        )
        items = result.scalars().all()
        recs = []
        for item in items:
            savings, confidence = self._estimate_savings(item, "hevc", learned_ratios)
            rec = Recommendation(
                media_item_id=item.id,
                type="codec_upgrade",
                severity="warning" if (item.file_size or 0) > 10_000_000_000 else "info",
                title=f"Upgrade {item.title} from {item.video_codec} to HEVC",
                description=(
                    f"Converting from {item.video_codec} to HEVC could save approximately "
                    f"{savings / 1_000_000_000:.1f} GB with minimal quality loss."
                ),
                estimated_savings=savings,
                confidence=confidence,
            )
            rec.priority_score = self._score_recommendation(rec, item)
            recs.append(rec)
        return recs

    async def _analyze_quality_overkill(self, thresholds: Dict,
                                         learned_ratios: Dict) -> List[Recommendation]:
        min_size = thresholds.get("overkill_min_size_gb", 30) * 1_000_000_000
        max_plays = thresholds.get("overkill_max_plays", 2)
        result = await self.session.execute(
            select(MediaItem).where(
                MediaItem.resolution_tier == "4K",
                MediaItem.is_hdr == True,  # noqa: E712
                MediaItem.play_count < max_plays,
                MediaItem.file_size > min_size,
            )
        )
        items = result.scalars().all()
        recs = []
        for item in items:
            savings, confidence = self._estimate_savings(item, "hevc", learned_ratios)
            # Downscaling to 1080p saves more — bump estimate
            savings = int(savings * 1.3)
            rec = Recommendation(
                media_item_id=item.id,
                type="quality_overkill",
                severity="info",
                title=f"{item.title} - 4K HDR with low play count",
                description=(
                    f"This 4K HDR file is {(item.file_size or 0) / 1_000_000_000:.1f} GB "
                    f"but has only been played {item.play_count} times. Consider downscaling to 1080p."
                ),
                estimated_savings=savings,
                confidence=confidence,
            )
            rec.priority_score = self._score_recommendation(rec, item)
            recs.append(rec)
        return recs

    async def _detect_duplicates(self) -> List[Recommendation]:
        result = await self.session.execute(
            select(MediaItem.title, MediaItem.year, func.count())
            .group_by(MediaItem.title, MediaItem.year)
            .having(func.count() > 1)
        )
        duplicates = result.all()
        recs = []
        for title, year, dup_count in duplicates:
            items_result = await self.session.execute(
                select(MediaItem).where(
                    MediaItem.title == title,
                    MediaItem.year == year,
                ).order_by(MediaItem.file_size.desc())
            )
            items = items_result.scalars().all()
            if len(items) > 1:
                savings = sum(i.file_size or 0 for i in items[1:])
                rec = Recommendation(
                    media_item_id=items[0].id,
                    type="duplicate",
                    severity="warning",
                    title=f"Duplicate detected: {title} ({year})",
                    description=(
                        f"Found {dup_count} copies of this title. "
                        f"Removing duplicates could save {savings / 1_000_000_000:.1f} GB."
                    ),
                    estimated_savings=savings,
                    confidence=1.0,
                )
                rec.priority_score = self._score_recommendation(rec, items[0])
                recs.append(rec)
        return recs

    async def _analyze_quality_gaps(self, thresholds: Dict) -> List[Recommendation]:
        bitrate_pct = thresholds.get("quality_gap_bitrate_pct", 40) / 100.0
        avg_result = await self.session.execute(
            select(func.avg(MediaItem.video_bitrate))
        )
        avg_bitrate = avg_result.scalar() or 0

        result = await self.session.execute(
            select(MediaItem).where(
                MediaItem.video_bitrate < avg_bitrate * bitrate_pct,
                MediaItem.video_bitrate.isnot(None),
            )
        )
        items = result.scalars().all()
        recs = []
        for item in items:
            rec = Recommendation(
                media_item_id=item.id,
                type="low_quality",
                severity="info",
                title=f"{item.title} - Below average quality",
                description=(
                    f"Bitrate ({item.video_bitrate} bps) is significantly below library average "
                    f"({int(avg_bitrate)} bps). Consider finding a higher quality source."
                ),
                estimated_savings=0,
                confidence=0.8,
            )
            rec.priority_score = self._score_recommendation(rec, item)
            recs.append(rec)
        return recs

    async def _analyze_storage_optimization(self, thresholds: Dict,
                                             learned_ratios: Dict) -> List[Recommendation]:
        min_size = thresholds.get("storage_opt_min_size_gb", 20) * 1_000_000_000
        top_n = thresholds.get("storage_opt_top_n", 20)
        result = await self.session.execute(
            select(MediaItem)
            .where(MediaItem.file_size > min_size)
            .order_by((MediaItem.file_size / func.max(MediaItem.play_count, 1)).desc())
            .limit(top_n)
        )
        items = result.scalars().all()
        recs = []
        for item in items:
            savings, confidence = self._estimate_savings(item, "hevc", learned_ratios)
            rec = Recommendation(
                media_item_id=item.id,
                type="storage_optimization",
                severity="info",
                title=f"{item.title} - High storage, low engagement",
                description=(
                    f"This file uses {(item.file_size or 0) / 1_000_000_000:.1f} GB "
                    f"but has only {item.play_count} plays. Compression could save "
                    f"{savings / 1_000_000_000:.1f} GB."
                ),
                estimated_savings=savings,
                confidence=confidence,
            )
            rec.priority_score = self._score_recommendation(rec, item)
            recs.append(rec)
        return recs

    # ── New Analyzers ───────────────────────────────────────────────────

    async def _analyze_audio_optimization(self, thresholds: Dict) -> List[Recommendation]:
        """Flag items with high-channel lossless audio that could be downmixed."""
        channel_threshold = thresholds.get("audio_channels_threshold", 6)
        result = await self.session.execute(
            select(MediaItem).where(
                MediaItem.audio_channels >= channel_threshold,
                MediaItem.audio_codec.isnot(None),
            )
        )
        items = result.scalars().all()
        recs = []
        for item in items:
            codec = (item.audio_codec or "").lower()
            is_lossless = any(lc in codec for lc in LOSSLESS_AUDIO)
            if not is_lossless:
                continue

            # Estimate audio savings: lossless 7.1 → AAC stereo can save ~15-25% of file
            audio_bitrate = item.audio_bitrate or 0
            file_size = item.file_size or 0
            if audio_bitrate > 0 and item.video_bitrate and item.video_bitrate > 0:
                audio_fraction = audio_bitrate / (audio_bitrate + item.video_bitrate)
                savings = int(file_size * audio_fraction * 0.8)  # ~80% of audio track size
            else:
                savings = int(file_size * 0.15)  # conservative estimate

            if savings < 100_000_000:  # Skip if less than 100 MB savings
                continue

            rec = Recommendation(
                media_item_id=item.id,
                type="audio_optimization",
                severity="info",
                title=f"{item.title} - Lossless {item.audio_channels}ch audio",
                description=(
                    f"This file has {item.audio_codec} {item.audio_channels}-channel audio. "
                    f"Converting to AAC could save ~{savings / 1_000_000_000:.1f} GB."
                ),
                estimated_savings=savings,
                confidence=0.6,
            )
            rec.priority_score = self._score_recommendation(rec, item)
            recs.append(rec)
        return recs

    async def _analyze_container_modernize(self, thresholds: Dict) -> List[Recommendation]:
        """Flag old container formats (.avi, .wmv, etc.) for remux to .mkv."""
        result = await self.session.execute(
            select(MediaItem).where(
                MediaItem.container.in_(list(OLD_CONTAINERS))
            )
        )
        items = result.scalars().all()
        recs = []
        for item in items:
            rec = Recommendation(
                media_item_id=item.id,
                type="container_modernize",
                severity="info",
                title=f"{item.title} - Remux from .{item.container} to .mkv",
                description=(
                    f"This file uses the legacy .{item.container} container. "
                    f"Remuxing to .mkv is very fast (no re-encode) and improves compatibility."
                ),
                estimated_savings=0,
                confidence=1.0,
            )
            rec.priority_score = self._score_recommendation(rec, item)
            recs.append(rec)
        return recs

    async def _analyze_hdr_to_sdr(self, thresholds: Dict,
                                   learned_ratios: Dict) -> List[Recommendation]:
        """Flag HDR content with low play counts for potential SDR conversion."""
        max_plays = thresholds.get("hdr_max_plays", 3)
        result = await self.session.execute(
            select(MediaItem).where(
                MediaItem.is_hdr == True,  # noqa: E712
                MediaItem.play_count <= max_plays,
            )
        )
        items = result.scalars().all()
        recs = []
        for item in items:
            savings, confidence = self._estimate_savings(item, "hevc", learned_ratios)
            rec = Recommendation(
                media_item_id=item.id,
                type="hdr_to_sdr",
                severity="info",
                title=f"{item.title} - HDR with low usage",
                description=(
                    f"This HDR file ({item.hdr_format or 'HDR'}) has only {item.play_count} plays. "
                    f"Converting to SDR with tone mapping could save ~{savings / 1_000_000_000:.1f} GB "
                    f"and improve compatibility with non-HDR displays."
                ),
                estimated_savings=savings,
                confidence=confidence * 0.8,  # slightly less confident due to tone mapping
            )
            rec.priority_score = self._score_recommendation(rec, item)
            recs.append(rec)
        return recs

    async def _analyze_batch_similar(self, thresholds: Dict,
                                      learned_ratios: Dict) -> List[Recommendation]:
        """Group items by (codec, resolution, library) and flag large groups for batch transcode."""
        min_group = thresholds.get("batch_min_group_size", 5)
        result = await self.session.execute(
            select(
                MediaItem.video_codec,
                MediaItem.resolution_tier,
                MediaItem.plex_library_id,
                func.count(),
                func.sum(MediaItem.file_size),
            ).where(
                MediaItem.video_codec.in_(list(UPGRADE_CODECS)),
            ).group_by(
                MediaItem.video_codec, MediaItem.resolution_tier, MediaItem.plex_library_id
            ).having(func.count() >= min_group)
        )
        groups = result.all()
        recs = []
        for codec, res, lib_id, count, total_size in groups:
            # Estimate savings for the whole group
            avg_size = (total_size or 0) / max(count, 1)
            key = ((codec or "").lower(), "hevc")
            if key in learned_ratios:
                ratio = learned_ratios[key]
                confidence = 0.9
            elif key in DEFAULT_RATIOS:
                ratio = DEFAULT_RATIOS[key]
                confidence = 0.5
            else:
                ratio = 0.55
                confidence = 0.2
            savings = int((total_size or 0) * (1 - ratio))

            rec = Recommendation(
                media_item_id=None,
                type="batch_similar",
                severity="info",
                title=f"Batch transcode {count} {codec} {res or 'mixed'} files to HEVC",
                description=(
                    f"{count} files using {codec} at {res or 'various'} resolution "
                    f"(total {(total_size or 0) / 1_000_000_000:.1f} GB). "
                    f"Batch transcoding to HEVC could save ~{savings / 1_000_000_000:.1f} GB."
                ),
                estimated_savings=savings,
                confidence=confidence,
                priority_score=min(100.0, round(
                    (math.log10(max((total_size or 0) / 1_000_000_000, 0.1) + 1) * 25)
                    + (CODEC_AGE.get((codec or "").lower(), 0) / 6 * 25)
                    + (confidence * 20)
                    + min(15.0, count * 0.5),
                    1,
                )),
            )
            recs.append(rec)
        return recs

    # ── Batch Queue ─────────────────────────────────────────────────────

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
