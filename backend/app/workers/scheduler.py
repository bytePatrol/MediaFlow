import asyncio
import logging

from app.workers.transcode_worker import TranscodeWorker
from app.workers.health_worker import HealthWorker
from app.workers.cloud_monitor import CloudMonitorWorker

logger = logging.getLogger(__name__)

_transcode_worker: TranscodeWorker | None = None
_health_worker: HealthWorker | None = None
_cloud_monitor: CloudMonitorWorker | None = None


async def start_scheduler():
    global _transcode_worker, _health_worker, _cloud_monitor

    _transcode_worker = TranscodeWorker()
    _health_worker = HealthWorker(interval=30)
    _cloud_monitor = CloudMonitorWorker(interval=60)

    asyncio.create_task(_transcode_worker.start())
    asyncio.create_task(_health_worker.start())
    asyncio.create_task(_cloud_monitor.start())
    logger.info("Scheduler started with TranscodeWorker, HealthWorker, and CloudMonitorWorker")


def get_transcode_worker():
    return _transcode_worker


async def stop_scheduler():
    if _transcode_worker:
        await _transcode_worker.stop()
    if _health_worker:
        await _health_worker.stop()
    if _cloud_monitor:
        await _cloud_monitor.stop()
    logger.info("Scheduler stopped")
