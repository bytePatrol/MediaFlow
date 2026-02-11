import asyncio
import logging

from sqlalchemy import select

from app.database import async_session_factory
from app.models.plex_server import PlexServer
from app.services.plex_service import PlexService
from app.api.websocket import manager

logger = logging.getLogger(__name__)


async def run_sync(server_id: int):
    async with async_session_factory() as session:
        result = await session.execute(
            select(PlexServer).where(PlexServer.id == server_id)
        )
        server = result.scalar_one_or_none()
        if not server:
            logger.error(f"Server {server_id} not found")
            return

        service = PlexService(session)

        await manager.broadcast("sync.progress", {
            "server_id": server_id,
            "status": "started",
            "progress": 0,
        })

        try:
            sync_result = await service.sync_library(server)

            await manager.broadcast("sync.completed", {
                "server_id": server_id,
                "items_synced": sync_result["items_synced"],
                "libraries_synced": sync_result["libraries_synced"],
                "duration_seconds": sync_result["duration_seconds"],
            })

            logger.info(f"Sync completed: {sync_result}")
        except Exception as e:
            logger.error(f"Sync failed for server {server_id}: {e}")
            await manager.broadcast("sync.progress", {
                "server_id": server_id,
                "status": "failed",
                "error": str(e),
            })
