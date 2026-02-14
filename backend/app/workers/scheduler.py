import asyncio
import logging
from datetime import datetime

from sqlalchemy import select

from app.database import async_session_factory
from app.models.app_settings import AppSetting
from app.workers.transcode_worker import TranscodeWorker
from app.workers.health_worker import HealthWorker
from app.workers.cloud_monitor import CloudMonitorWorker
from app.workers.folder_watcher import FolderWatcherWorker

logger = logging.getLogger(__name__)

# Interval mapping for auto-analysis
_AUTO_ANALYZE_INTERVALS = {
    "daily": 24 * 60 * 60,   # 86400 seconds
    "weekly": 7 * 24 * 60 * 60,  # 604800 seconds
}


async def is_within_active_hours() -> bool:
    """Check if the current local time falls within the configured active hours window.

    Returns True (always active) if scheduling is disabled or settings are missing.
    Handles overnight windows (e.g. 22:00 to 06:00 that span midnight).
    """
    async with async_session_factory() as session:
        # Load all schedule.* settings in one query
        result = await session.execute(
            select(AppSetting).where(AppSetting.key.like("schedule.%"))
        )
        settings = {s.key: s.value for s in result.scalars().all()}

    enabled = settings.get("schedule.enabled", "false")
    if enabled != "true":
        return True  # Scheduling disabled — always active

    start_str = settings.get("schedule.active_hours_start", "00:00")
    end_str = settings.get("schedule.active_hours_end", "23:59")
    active_days_str = settings.get("schedule.active_days", "0,1,2,3,4,5,6")

    # Parse active days (0=Monday, 6=Sunday)
    try:
        active_days = set(int(d.strip()) for d in active_days_str.split(",") if d.strip())
    except (ValueError, TypeError):
        active_days = set(range(7))

    now = datetime.now()
    current_day = now.weekday()  # 0=Monday

    if current_day not in active_days:
        return False

    try:
        start_h, start_m = (int(x) for x in start_str.split(":"))
        end_h, end_m = (int(x) for x in end_str.split(":"))
    except (ValueError, TypeError):
        return True  # Malformed settings — fall back to always active

    current_minutes = now.hour * 60 + now.minute
    start_minutes = start_h * 60 + start_m
    end_minutes = end_h * 60 + end_m

    if start_minutes <= end_minutes:
        # Same-day window (e.g. 08:00 to 18:00)
        return start_minutes <= current_minutes < end_minutes
    else:
        # Overnight window (e.g. 22:00 to 06:00)
        return current_minutes >= start_minutes or current_minutes < end_minutes


async def _auto_analyze_loop():
    """Background loop that runs auto-analysis at the configured interval.

    Reads `intel.auto_analyze_interval` setting each cycle:
    - "disabled" (default): no auto-analysis
    - "daily": run once every 24 hours
    - "weekly": run once every 7 days

    Sleeps in 60-second chunks so interval changes take effect within a minute.
    """
    last_run_time: float = 0.0

    while True:
        try:
            await asyncio.sleep(60)  # Check every 60 seconds

            # Read the current interval setting
            async with async_session_factory() as session:
                result = await session.execute(
                    select(AppSetting).where(AppSetting.key == "intel.auto_analyze_interval")
                )
                setting = result.scalar_one_or_none()
                interval_value = setting.value if setting else "disabled"

            interval_seconds = _AUTO_ANALYZE_INTERVALS.get(interval_value)
            if interval_seconds is None:
                # disabled or unrecognized value — skip
                continue

            now = asyncio.get_event_loop().time()
            if last_run_time == 0.0 or (now - last_run_time) >= interval_seconds:
                logger.info("Auto-analysis triggered (interval=%s)", interval_value)
                try:
                    async with async_session_factory() as session:
                        from app.services.recommendation_service import RecommendationService
                        service = RecommendationService(session)
                        result = await service.run_full_analysis(trigger="auto")
                        logger.info(
                            "Auto-analysis completed: %d recommendations generated",
                            result["recommendations_generated"],
                        )
                except Exception as exc:
                    logger.error("Auto-analysis failed: %s", exc)
                last_run_time = asyncio.get_event_loop().time()

        except asyncio.CancelledError:
            break
        except Exception as exc:
            logger.error("Auto-analyze loop error: %s", exc)
            await asyncio.sleep(60)


_SYNC_INTERVALS = {
    "6h": 6 * 3600,
    "12h": 12 * 3600,
    "daily": 24 * 3600,
    "weekly": 7 * 24 * 3600,
}

_library_sync_task: asyncio.Task | None = None


async def _library_sync_loop():
    """Background loop that syncs Plex libraries at the configured interval."""
    last_sync_time: float = 0.0

    while True:
        try:
            await asyncio.sleep(60)

            async with async_session_factory() as session:
                result = await session.execute(
                    select(AppSetting).where(AppSetting.key == "sync.schedule_enabled")
                )
                setting = result.scalar_one_or_none()
                if not setting or setting.value != "true":
                    continue

                result = await session.execute(
                    select(AppSetting).where(AppSetting.key == "sync.schedule_interval")
                )
                interval_setting = result.scalar_one_or_none()
                interval_value = interval_setting.value if interval_setting else "daily"

            interval_seconds = _SYNC_INTERVALS.get(interval_value)
            if interval_seconds is None:
                continue

            now = asyncio.get_event_loop().time()
            if last_sync_time == 0.0 or (now - last_sync_time) >= interval_seconds:
                logger.info("Scheduled library sync triggered (interval=%s)", interval_value)
                try:
                    async with async_session_factory() as session:
                        from app.services.plex_service import PlexService
                        from app.models.plex_server import PlexServer
                        servers = (await session.execute(
                            select(PlexServer).where(PlexServer.is_active == True)
                        )).scalars().all()
                        for server in servers:
                            svc = PlexService(session)
                            await svc.sync_server(server.id)
                            logger.info("Synced server: %s", server.name)

                        # Optionally run analysis after sync
                        auto_analyze_result = await session.execute(
                            select(AppSetting).where(AppSetting.key == "intel.auto_analyze_on_sync")
                        )
                        auto_setting = auto_analyze_result.scalar_one_or_none()
                        if auto_setting and auto_setting.value != "false":
                            from app.services.recommendation_service import RecommendationService
                            rec_svc = RecommendationService(session)
                            await rec_svc.run_full_analysis(trigger="auto")
                            logger.info("Post-sync analysis completed")
                except Exception as exc:
                    logger.error("Scheduled sync failed: %s", exc)
                last_sync_time = asyncio.get_event_loop().time()

        except asyncio.CancelledError:
            break
        except Exception as exc:
            logger.error("Library sync loop error: %s", exc)
            await asyncio.sleep(60)


_transcode_worker: TranscodeWorker | None = None
_health_worker: HealthWorker | None = None
_cloud_monitor: CloudMonitorWorker | None = None
_auto_analyze_task: asyncio.Task | None = None
_folder_watcher: FolderWatcherWorker | None = None


async def start_scheduler():
    global _transcode_worker, _health_worker, _cloud_monitor, _auto_analyze_task, _library_sync_task, _folder_watcher

    _transcode_worker = TranscodeWorker()
    _health_worker = HealthWorker(interval=30)
    _cloud_monitor = CloudMonitorWorker(interval=60)
    _folder_watcher = FolderWatcherWorker()

    asyncio.create_task(_transcode_worker.start())
    asyncio.create_task(_health_worker.start())
    asyncio.create_task(_cloud_monitor.start())
    _auto_analyze_task = asyncio.create_task(_auto_analyze_loop())
    _library_sync_task = asyncio.create_task(_library_sync_loop())
    asyncio.create_task(_folder_watcher.start())
    logger.info("Scheduler started with TranscodeWorker, HealthWorker, CloudMonitorWorker, AutoAnalyze, LibrarySyncLoop, and FolderWatcher")


def get_transcode_worker():
    return _transcode_worker


async def stop_scheduler():
    if _transcode_worker:
        await _transcode_worker.stop()
    if _health_worker:
        await _health_worker.stop()
    if _cloud_monitor:
        await _cloud_monitor.stop()
    if _auto_analyze_task:
        _auto_analyze_task.cancel()
        try:
            await _auto_analyze_task
        except asyncio.CancelledError:
            pass
    if _library_sync_task:
        _library_sync_task.cancel()
        try:
            await _library_sync_task
        except asyncio.CancelledError:
            pass
    if _folder_watcher:
        await _folder_watcher.stop()
    logger.info("Scheduler stopped")
