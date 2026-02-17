import asyncio
import logging
import math
from datetime import datetime, timedelta
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
                                   include_dismissed: bool = False,
                                   library_id: Optional[int] = None) -> List[RecommendationResponse]:
        query = select(Recommendation)
        if type:
            query = query.where(Recommendation.type == type)
        if not include_dismissed:
            query = query.where(Recommendation.is_dismissed == False)  # noqa: E712
        if library_id is not None:
            # Filter by library: join through media_item to check plex_library_id
            query = query.join(MediaItem, Recommendation.media_item_id == MediaItem.id).where(
                MediaItem.plex_library_id == library_id
            )
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

    async def get_summary(self, library_id: Optional[int] = None) -> RecommendationSummary:
        if library_id is not None:
            total_result = await self.session.execute(
                select(func.count()).select_from(Recommendation)
                .join(MediaItem, Recommendation.media_item_id == MediaItem.id)
                .where(MediaItem.plex_library_id == library_id)
            )
        else:
            total_result = await self.session.execute(
                select(func.count()).select_from(Recommendation)
            )
        total = total_result.scalar() or 0

        type_query = select(Recommendation.type, func.count()).group_by(Recommendation.type)
        if library_id is not None:
            type_query = type_query.join(MediaItem, Recommendation.media_item_id == MediaItem.id).where(
                MediaItem.plex_library_id == library_id
            )
        type_result = await self.session.execute(type_query)
        by_type = {t: c for t, c in type_result.all()}

        savings_query = select(func.sum(Recommendation.estimated_savings)).where(
            Recommendation.is_dismissed == False  # noqa: E712
        )
        if library_id is not None:
            savings_query = savings_query.join(MediaItem, Recommendation.media_item_id == MediaItem.id).where(
                MediaItem.plex_library_id == library_id
            )
        savings_result = await self.session.execute(savings_query)
        total_savings = savings_result.scalar() or 0

        dismissed_query = select(func.count()).select_from(Recommendation).where(
            Recommendation.is_dismissed == True  # noqa: E712
        )
        if library_id is not None:
            dismissed_query = dismissed_query.join(MediaItem, Recommendation.media_item_id == MediaItem.id).where(
                MediaItem.plex_library_id == library_id
            )
        dismissed_result = await self.session.execute(dismissed_query)
        dismissed = dismissed_result.scalar() or 0

        actioned_query = select(func.count()).select_from(Recommendation).where(
            Recommendation.is_actioned == True  # noqa: E712
        )
        if library_id is not None:
            actioned_query = actioned_query.join(MediaItem, Recommendation.media_item_id == MediaItem.id).where(
                MediaItem.plex_library_id == library_id
            )
        actioned_result = await self.session.execute(actioned_query)
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
        all_recs.extend(await self._analyze_viewing_patterns(thresholds))

        # Apply learned user preferences to suppress unwanted recommendations
        prefs = await self._load_user_preferences()
        all_recs = await self._apply_preference_filter(all_recs, prefs)

        # Compute cost-benefit and attach to run
        for rec in all_recs:
            rec.analysis_run_id = run.id
            # Enrich with cost-benefit data
            item = None
            if rec.media_item_id:
                item_result = await self.session.execute(
                    select(MediaItem).where(MediaItem.id == rec.media_item_id)
                )
                item = item_result.scalar_one_or_none()
            await self._compute_cost_benefit(rec, item)
            self.session.add(rec)

        await self.session.flush()

        # Update run with completion stats
        total_savings = sum(r.estimated_savings or 0 for r in all_recs)
        run.completed_at = datetime.utcnow()
        run.total_items_analyzed = total_items
        run.recommendations_generated = len(all_recs)
        run.total_estimated_savings = total_savings
        await self.session.commit()

        # Broadcast via WebSocket + fire notification
        try:
            from app.api.websocket import manager
            await manager.broadcast("analysis.completed", {
                "run_id": run.id,
                "recommendations_generated": len(all_recs),
                "total_estimated_savings": total_savings,
            })
        except Exception:
            pass
        try:
            from app.utils.notify import fire_notification
            await fire_notification("analysis.completed", {
                "run_id": run.id,
                "recommendations_generated": len(all_recs),
                "total_estimated_savings": total_savings,
            })
        except Exception:
            pass

        try:
            from app.services.automation_engine import AutomationEngine
            asyncio.create_task(AutomationEngine.fire_event("analysis_complete", {
                "run_id": run.id,
                "recommendations_generated": len(all_recs),
                "total_estimated_savings": total_savings,
                "library_id": None,
            }))
        except Exception:
            pass

        return {
            "run_id": run.id,
            "trigger": trigger,
            "total_items_analyzed": total_items,
            "recommendations_generated": len(all_recs),
            "total_estimated_savings": total_savings,
        }

    async def run_library_analysis(self, library_id: int, trigger: str = "manual") -> Dict[str, Any]:
        """Run all analyzers scoped to a single library and return an analysis run summary."""
        # Create analysis run record
        run = AnalysisRun(trigger=trigger, library_id=library_id)
        self.session.add(run)
        await self.session.flush()

        # Get media_item_ids for this library
        lib_item_ids_result = await self.session.execute(
            select(MediaItem.id).where(MediaItem.plex_library_id == library_id)
        )
        lib_item_ids = [row[0] for row in lib_item_ids_result.all()]

        # Clear non-dismissed, non-actioned recommendations for items in this library
        if lib_item_ids:
            await self.session.execute(
                delete(Recommendation).where(
                    Recommendation.is_actioned == False,  # noqa: E712
                    Recommendation.is_dismissed == False,  # noqa: E712
                    Recommendation.media_item_id.in_(lib_item_ids),
                )
            )
        await self.session.commit()

        # Load configurable thresholds
        thresholds = await self._load_thresholds()

        # Load learned compression ratios from job history
        learned_ratios = await self._get_learned_ratios()

        # Count total items for the run
        total_items = len(lib_item_ids)

        # Run all analyzers scoped to library
        all_recs: List[Recommendation] = []
        all_recs.extend(await self._analyze_codec_modernization(thresholds, learned_ratios, library_id=library_id))
        all_recs.extend(await self._analyze_quality_overkill(thresholds, learned_ratios, library_id=library_id))
        all_recs.extend(await self._detect_duplicates(library_id=library_id))
        all_recs.extend(await self._analyze_quality_gaps(thresholds, library_id=library_id))
        all_recs.extend(await self._analyze_storage_optimization(thresholds, learned_ratios, library_id=library_id))
        all_recs.extend(await self._analyze_audio_optimization(thresholds, library_id=library_id))
        all_recs.extend(await self._analyze_container_modernize(thresholds, library_id=library_id))
        all_recs.extend(await self._analyze_hdr_to_sdr(thresholds, learned_ratios, library_id=library_id))
        all_recs.extend(await self._analyze_batch_similar(thresholds, learned_ratios, library_id=library_id))
        all_recs.extend(await self._analyze_viewing_patterns(thresholds, library_id=library_id))

        # Apply learned user preferences to suppress unwanted recommendations
        prefs = await self._load_user_preferences()
        all_recs = await self._apply_preference_filter(all_recs, prefs)

        # Compute cost-benefit and attach to run
        for rec in all_recs:
            rec.analysis_run_id = run.id
            # Enrich with cost-benefit data
            item = None
            if rec.media_item_id:
                item_result = await self.session.execute(
                    select(MediaItem).where(MediaItem.id == rec.media_item_id)
                )
                item = item_result.scalar_one_or_none()
            await self._compute_cost_benefit(rec, item)
            self.session.add(rec)

        await self.session.flush()

        # Update run with completion stats
        total_savings = sum(r.estimated_savings or 0 for r in all_recs)
        run.completed_at = datetime.utcnow()
        run.total_items_analyzed = total_items
        run.recommendations_generated = len(all_recs)
        run.total_estimated_savings = total_savings
        await self.session.commit()

        # Broadcast via WebSocket + fire notification
        try:
            from app.api.websocket import manager
            await manager.broadcast("analysis.completed", {
                "run_id": run.id,
                "library_id": library_id,
                "recommendations_generated": len(all_recs),
                "total_estimated_savings": total_savings,
            })
        except Exception:
            pass
        try:
            from app.utils.notify import fire_notification
            await fire_notification("analysis.completed", {
                "run_id": run.id,
                "library_id": library_id,
                "recommendations_generated": len(all_recs),
                "total_estimated_savings": total_savings,
            })
        except Exception:
            pass

        try:
            from app.services.automation_engine import AutomationEngine
            asyncio.create_task(AutomationEngine.fire_event("analysis_complete", {
                "run_id": run.id,
                "recommendations_generated": len(all_recs),
                "total_estimated_savings": total_savings,
                "library_id": library_id,
            }))
        except Exception:
            pass

        return {
            "run_id": run.id,
            "trigger": trigger,
            "library_id": library_id,
            "total_items_analyzed": total_items,
            "recommendations_generated": len(all_recs),
            "total_estimated_savings": total_savings,
        }

    async def get_analysis_history(self, limit: int = 20) -> List[Dict[str, Any]]:
        from app.models.plex_library import PlexLibrary
        result = await self.session.execute(
            select(AnalysisRun, PlexLibrary.title)
            .outerjoin(PlexLibrary, AnalysisRun.library_id == PlexLibrary.id)
            .order_by(AnalysisRun.id.desc())
            .limit(limit)
        )
        rows = result.all()
        return [
            {
                "id": r.id,
                "started_at": r.started_at.isoformat() if r.started_at else None,
                "completed_at": r.completed_at.isoformat() if r.completed_at else None,
                "total_items_analyzed": r.total_items_analyzed,
                "recommendations_generated": r.recommendations_generated,
                "total_estimated_savings": r.total_estimated_savings,
                "trigger": r.trigger,
                "library_id": r.library_id,
                "library_title": lib_title,
            }
            for r, lib_title in rows
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

    # ── Learn from Dismissal History ──────────────────────────────────

    async def _load_user_preferences(self) -> Dict[str, Any]:
        """Learn user preferences from dismiss history to suppress unwanted recommendations."""
        from app.models.recommendation_feedback import RecommendationFeedback

        prefs: Dict[str, Any] = {
            "suppress_resolutions": set(),  # e.g., {"4K"} if user always dismisses 4K recs
            "suppress_codecs": set(),       # e.g., {"all"} if user doesn't want codec change recs
            "suppress_types": set(),        # e.g., {"hdr_to_sdr"} if always dismissed
            "min_savings_gb": 0.0,          # learned minimum savings threshold
            "calibration_factor": 1.0,      # actual/estimated savings ratio
        }

        # 1. Count dismissals by reason
        reason_result = await self.session.execute(
            select(RecommendationFeedback.dismiss_reason, func.count())
            .where(
                RecommendationFeedback.action == "dismissed",
                RecommendationFeedback.dismiss_reason.isnot(None),
            )
            .group_by(RecommendationFeedback.dismiss_reason)
        )
        reason_counts = {r: c for r, c in reason_result.all()}

        # Apply structured reason patterns (need at least 3 dismissals to learn)
        if reason_counts.get("keep_4k", 0) >= 3:
            prefs["suppress_resolutions"].add("4K")

        if reason_counts.get("keep_codec", 0) >= 3:
            prefs["suppress_codecs"].add("all")

        # 2. Check if specific rec types are consistently dismissed (>70% dismiss rate with 5+ total)
        type_stats_result = await self.session.execute(
            select(
                Recommendation.type,
                func.count().filter(Recommendation.is_dismissed == True),  # noqa: E712
                func.count(),
            ).group_by(Recommendation.type)
        )
        for rec_type, dismissed_count, total_count in type_stats_result.all():
            if total_count >= 5 and dismissed_count / total_count > 0.7:
                prefs["suppress_types"].add(rec_type)

        # 3. Learn minimum savings threshold from dismissed recs with small savings
        #    If user frequently dismisses recs, use the average dismissed savings as a floor
        small_dismiss_result = await self.session.execute(
            select(func.avg(RecommendationFeedback.estimated_savings))
            .where(
                RecommendationFeedback.action == "dismissed",
                RecommendationFeedback.estimated_savings.isnot(None),
                RecommendationFeedback.estimated_savings > 0,
            )
        )
        avg_dismissed_savings = small_dismiss_result.scalar()

        total_dismissals_result = await self.session.execute(
            select(func.count()).select_from(RecommendationFeedback)
            .where(
                RecommendationFeedback.action == "dismissed",
                RecommendationFeedback.estimated_savings.isnot(None),
                RecommendationFeedback.estimated_savings > 0,
            )
        )
        total_dismiss_count = total_dismissals_result.scalar() or 0

        if total_dismiss_count >= 5 and avg_dismissed_savings is not None:
            # Set floor to 50% of the average dismissed savings (conservative)
            prefs["min_savings_gb"] = (avg_dismissed_savings * 0.5) / 1_000_000_000

        # 4. Learn calibration factor from actual vs estimated savings
        calibration_result = await self.session.execute(
            select(
                func.avg(RecommendationFeedback.actual_savings),
                func.avg(RecommendationFeedback.estimated_savings),
            ).where(
                RecommendationFeedback.actual_savings.isnot(None),
                RecommendationFeedback.estimated_savings.isnot(None),
                RecommendationFeedback.estimated_savings > 0,
            )
        )
        cal_row = calibration_result.first()
        if cal_row and cal_row[0] is not None and cal_row[1] is not None and cal_row[1] > 0:
            prefs["calibration_factor"] = cal_row[0] / cal_row[1]

        # 5. Count dismissals by resolution from feedback records
        res_dismiss_result = await self.session.execute(
            select(RecommendationFeedback.resolution, func.count())
            .where(
                RecommendationFeedback.action == "dismissed",
                RecommendationFeedback.resolution.isnot(None),
            )
            .group_by(RecommendationFeedback.resolution)
        )
        for resolution, count in res_dismiss_result.all():
            if count >= 3:
                prefs["suppress_resolutions"].add(resolution)

        logger.info(
            "Loaded user preferences from %d dismissals: suppress_types=%s, "
            "suppress_resolutions=%s, suppress_codecs=%s, min_savings_gb=%.2f, "
            "calibration_factor=%.3f",
            total_dismiss_count,
            prefs["suppress_types"],
            prefs["suppress_resolutions"],
            prefs["suppress_codecs"],
            prefs["min_savings_gb"],
            prefs["calibration_factor"],
        )
        return prefs

    async def _apply_preference_filter(
        self, all_recs: List[Recommendation], prefs: Dict[str, Any]
    ) -> List[Recommendation]:
        """Filter out recommendations suppressed by learned user preferences."""
        suppress_types = prefs.get("suppress_types", set())
        suppress_resolutions = prefs.get("suppress_resolutions", set())
        suppress_codecs = prefs.get("suppress_codecs", set())
        min_savings = prefs.get("min_savings_gb", 0) * 1_000_000_000
        calibration = prefs.get("calibration_factor", 1.0)

        # If nothing learned, skip filtering entirely
        if (
            not suppress_types
            and not suppress_resolutions
            and not suppress_codecs
            and min_savings <= 0
            and calibration == 1.0
        ):
            return all_recs

        filtered: List[Recommendation] = []
        suppressed_count = 0

        for rec in all_recs:
            # Check type suppression
            if rec.type in suppress_types:
                suppressed_count += 1
                continue

            # Check resolution suppression (need to look up media item)
            if suppress_resolutions and rec.media_item_id:
                item_result = await self.session.execute(
                    select(MediaItem.resolution_tier).where(MediaItem.id == rec.media_item_id)
                )
                res = item_result.scalar()
                if res in suppress_resolutions:
                    suppressed_count += 1
                    continue

            # Check codec suppression (suppress all codec change recommendations)
            if "all" in suppress_codecs and rec.type in ("codec_upgrade", "storage_optimization"):
                suppressed_count += 1
                continue

            # Apply calibration factor to savings estimates
            if calibration != 1.0 and rec.estimated_savings:
                rec.estimated_savings = int(rec.estimated_savings * calibration)

            # Check minimum savings threshold (after calibration)
            if min_savings > 0 and (rec.estimated_savings or 0) < min_savings:
                suppressed_count += 1
                continue

            filtered.append(rec)

        if suppressed_count > 0:
            logger.info(
                "Preference filter suppressed %d/%d recommendations",
                suppressed_count,
                len(all_recs),
            )

        return filtered

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

    async def _compute_cost_benefit(self, rec: Recommendation, item: Optional[MediaItem]):
        """Compute cost-benefit metrics for a recommendation."""
        if not item or not rec.estimated_savings:
            return

        duration_ms = item.duration_ms or 0
        duration_hours = duration_ms / 3_600_000

        # Estimate transcode time from historical FPS
        source_codec = (item.video_codec or "").lower()
        target_codec = "hevc"  # Default target

        fps_result = await self.session.execute(
            select(func.avg(JobLog.avg_fps), func.count())
            .where(
                JobLog.status == "completed",
                JobLog.source_codec.ilike(f"%{source_codec}%"),
                JobLog.avg_fps.isnot(None),
                JobLog.avg_fps > 0,
            )
        )
        fps_row = fps_result.first()
        avg_fps = fps_row[0] if fps_row and fps_row[0] else None
        sample_count = fps_row[1] if fps_row else 0

        if avg_fps and avg_fps > 0 and item.frame_rate and item.frame_rate > 0:
            total_frames = (duration_ms / 1000) * item.frame_rate
            estimated_seconds = total_frames / avg_fps
        elif duration_hours > 0:
            # Fallback: assume 30 FPS encode speed
            estimated_seconds = (duration_ms / 1000) * (item.frame_rate or 24) / 30
        else:
            estimated_seconds = None

        rec.estimated_transcode_time = estimated_seconds

        # Estimate cloud cost
        if estimated_seconds:
            # Get cheapest cloud worker hourly rate
            from app.models.worker_server import WorkerServer
            cost_result = await self.session.execute(
                select(func.min(WorkerServer.hourly_cost))
                .where(WorkerServer.hourly_cost.isnot(None), WorkerServer.hourly_cost > 0)
            )
            min_hourly = cost_result.scalar()
            if min_hourly:
                rec.estimated_cloud_cost = round((estimated_seconds / 3600) * min_hourly, 4)

        # Compute ROI score: savings in GB per dollar (or per hour if no cost)
        savings_gb = (rec.estimated_savings or 0) / 1_000_000_000
        if rec.estimated_cloud_cost and rec.estimated_cloud_cost > 0:
            rec.roi_score = round(savings_gb / rec.estimated_cloud_cost, 2)
        elif estimated_seconds and estimated_seconds > 0:
            rec.roi_score = round(savings_gb / (estimated_seconds / 3600), 2)

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
                                            learned_ratios: Dict,
                                            library_id: Optional[int] = None) -> List[Recommendation]:
        query = select(MediaItem).where(
            MediaItem.video_codec.in_(list(UPGRADE_CODECS))
        )
        if library_id is not None:
            query = query.where(MediaItem.plex_library_id == library_id)
        result = await self.session.execute(query)
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
                                         learned_ratios: Dict,
                                         library_id: Optional[int] = None) -> List[Recommendation]:
        min_size = thresholds.get("overkill_min_size_gb", 30) * 1_000_000_000
        max_plays = thresholds.get("overkill_max_plays", 2)
        query = select(MediaItem).where(
            MediaItem.resolution_tier == "4K",
            MediaItem.is_hdr == True,  # noqa: E712
            MediaItem.play_count < max_plays,
            MediaItem.file_size > min_size,
        )
        if library_id is not None:
            query = query.where(MediaItem.plex_library_id == library_id)
        result = await self.session.execute(query)
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

    async def _detect_duplicates(self, library_id: Optional[int] = None) -> List[Recommendation]:
        dup_query = select(MediaItem.title, MediaItem.year, func.count())
        if library_id is not None:
            dup_query = dup_query.where(MediaItem.plex_library_id == library_id)
        dup_query = dup_query.group_by(MediaItem.title, MediaItem.year).having(func.count() > 1)
        result = await self.session.execute(dup_query)
        duplicates = result.all()
        recs = []
        for title, year, dup_count in duplicates:
            items_query = select(MediaItem).where(
                MediaItem.title == title,
                MediaItem.year == year,
            )
            if library_id is not None:
                items_query = items_query.where(MediaItem.plex_library_id == library_id)
            items_query = items_query.order_by(MediaItem.file_size.desc())
            items_result = await self.session.execute(items_query)
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

    async def _analyze_quality_gaps(self, thresholds: Dict,
                                     library_id: Optional[int] = None) -> List[Recommendation]:
        bitrate_pct = thresholds.get("quality_gap_bitrate_pct", 40) / 100.0
        avg_query = select(func.avg(MediaItem.video_bitrate))
        if library_id is not None:
            avg_query = avg_query.where(MediaItem.plex_library_id == library_id)
        avg_result = await self.session.execute(avg_query)
        avg_bitrate = avg_result.scalar() or 0

        query = select(MediaItem).where(
            MediaItem.video_bitrate < avg_bitrate * bitrate_pct,
            MediaItem.video_bitrate.isnot(None),
        )
        if library_id is not None:
            query = query.where(MediaItem.plex_library_id == library_id)
        result = await self.session.execute(query)
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
                                             learned_ratios: Dict,
                                             library_id: Optional[int] = None) -> List[Recommendation]:
        min_size = thresholds.get("storage_opt_min_size_gb", 20) * 1_000_000_000
        top_n = thresholds.get("storage_opt_top_n", 20)
        query = select(MediaItem).where(MediaItem.file_size > min_size)
        if library_id is not None:
            query = query.where(MediaItem.plex_library_id == library_id)
        query = query.order_by((MediaItem.file_size / func.max(MediaItem.play_count, 1)).desc()).limit(top_n)
        result = await self.session.execute(query)
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

    async def _analyze_audio_optimization(self, thresholds: Dict,
                                           library_id: Optional[int] = None) -> List[Recommendation]:
        """Flag items with high-channel lossless audio that could be downmixed."""
        channel_threshold = thresholds.get("audio_channels_threshold", 6)
        query = select(MediaItem).where(
            MediaItem.audio_channels >= channel_threshold,
            MediaItem.audio_codec.isnot(None),
        )
        if library_id is not None:
            query = query.where(MediaItem.plex_library_id == library_id)
        result = await self.session.execute(query)
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

    async def _analyze_container_modernize(self, thresholds: Dict,
                                            library_id: Optional[int] = None) -> List[Recommendation]:
        """Flag old container formats (.avi, .wmv, etc.) for remux to .mkv."""
        query = select(MediaItem).where(
            MediaItem.container.in_(list(OLD_CONTAINERS))
        )
        if library_id is not None:
            query = query.where(MediaItem.plex_library_id == library_id)
        result = await self.session.execute(query)
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
                                   learned_ratios: Dict,
                                   library_id: Optional[int] = None) -> List[Recommendation]:
        """Flag HDR content with low play counts for potential SDR conversion."""
        max_plays = thresholds.get("hdr_max_plays", 3)
        query = select(MediaItem).where(
            MediaItem.is_hdr == True,  # noqa: E712
            MediaItem.play_count <= max_plays,
        )
        if library_id is not None:
            query = query.where(MediaItem.plex_library_id == library_id)
        result = await self.session.execute(query)
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
                                      learned_ratios: Dict,
                                      library_id: Optional[int] = None) -> List[Recommendation]:
        """Group items by (codec, resolution, library) and flag large groups for batch transcode."""
        min_group = thresholds.get("batch_min_group_size", 5)
        batch_query = select(
            MediaItem.video_codec,
            MediaItem.resolution_tier,
            MediaItem.plex_library_id,
            func.count(),
            func.sum(MediaItem.file_size),
        ).where(
            MediaItem.video_codec.in_(list(UPGRADE_CODECS)),
        )
        if library_id is not None:
            batch_query = batch_query.where(MediaItem.plex_library_id == library_id)
        batch_query = batch_query.group_by(
            MediaItem.video_codec, MediaItem.resolution_tier, MediaItem.plex_library_id
        ).having(func.count() >= min_group)
        result = await self.session.execute(batch_query)
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

    async def _analyze_viewing_patterns(self, thresholds: Dict,
                                          library_id: Optional[int] = None) -> List[Recommendation]:
        """Analyze viewing patterns to recommend compression or quality upgrades."""
        recs = []
        now = datetime.utcnow()
        two_years_ago = now - timedelta(days=730)

        # 1. Never-watched items (play_count == 0 AND last_viewed_at is None) > 5 GB
        never_query = select(MediaItem).where(
            MediaItem.play_count == 0,
            MediaItem.last_viewed_at.is_(None),
            MediaItem.file_size > 5_000_000_000,
        )
        if library_id is not None:
            never_query = never_query.where(MediaItem.plex_library_id == library_id)
        result = await self.session.execute(never_query)
        never_watched = result.scalars().all()

        for item in never_watched:
            rec = Recommendation(
                media_item_id=item.id,
                type="viewing_pattern",
                severity="info",
                title=f"{item.title} - Never watched",
                description=(
                    "This file has never been viewed. Consider aggressive compression to save storage."
                ),
                estimated_savings=int((item.file_size or 0) * 0.50),
                confidence=0.7,
            )
            rec.priority_score = self._score_recommendation(rec, item)
            recs.append(rec)

        # 2. Heavily-watched items (play_count >= 10) with old codecs
        heavy_query = select(MediaItem).where(
            MediaItem.play_count >= 10,
            MediaItem.video_codec.in_(list(UPGRADE_CODECS)),
        )
        if library_id is not None:
            heavy_query = heavy_query.where(MediaItem.plex_library_id == library_id)
        result = await self.session.execute(heavy_query)
        heavily_watched = result.scalars().all()

        for item in heavily_watched:
            rec = Recommendation(
                media_item_id=item.id,
                type="viewing_pattern",
                severity="info",
                title=f"{item.title} - Frequently watched ({item.play_count} plays)",
                description=(
                    "This popular title deserves optimal quality. Consider upgrading to best available codec."
                ),
                estimated_savings=0,
                confidence=0.8,
            )
            rec.priority_score = self._score_recommendation(rec, item)
            recs.append(rec)

        # 3. Not watched in 2+ years, > 3 GB
        stale_query = select(MediaItem).where(
            MediaItem.last_viewed_at.isnot(None),
            MediaItem.last_viewed_at < two_years_ago,
            MediaItem.file_size > 3_000_000_000,
        )
        if library_id is not None:
            stale_query = stale_query.where(MediaItem.plex_library_id == library_id)
        result = await self.session.execute(stale_query)
        stale_items = result.scalars().all()

        for item in stale_items:
            years_since = (now - item.last_viewed_at).days // 365
            last_date = item.last_viewed_at.strftime("%b %d, %Y")
            rec = Recommendation(
                media_item_id=item.id,
                type="viewing_pattern",
                severity="info",
                title=f"{item.title} - Not watched in {years_since} years",
                description=(
                    f"This title hasn't been viewed since {last_date}. "
                    f"Consider aggressive compression or archival codec."
                ),
                estimated_savings=int((item.file_size or 0) * 0.45),
                confidence=0.6,
            )
            rec.priority_score = self._score_recommendation(rec, item)
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
