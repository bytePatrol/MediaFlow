import asyncio
import logging
import os
from datetime import datetime
from typing import Set

from sqlalchemy import select

from app.database import async_session_factory
from app.models.watch_folder import WatchFolder
from app.models.transcode_job import TranscodeJob

logger = logging.getLogger(__name__)


class FolderWatcherWorker:
    def __init__(self, interval: int = 30):
        self.interval = interval
        self.running = True
        self._known_files: dict[int, Set[str]] = {}  # folder_id -> set of known file paths

    async def start(self):
        logger.info("FolderWatcherWorker started")
        # Initial scan to build known files set
        await self._initial_scan()
        while self.running:
            try:
                await self._poll_folders()
            except Exception as e:
                logger.error(f"Folder watch error: {e}")
            await asyncio.sleep(self.interval)

    async def stop(self):
        self.running = False

    async def _initial_scan(self):
        """Build initial file set for all enabled watch folders."""
        async with async_session_factory() as session:
            result = await session.execute(
                select(WatchFolder).where(WatchFolder.is_enabled == True)
            )
            folders = result.scalars().all()
            for folder in folders:
                files = self._scan_directory(folder.path, folder.extensions)
                self._known_files[folder.id] = files
                logger.info(f"Initial scan: {len(files)} files in {folder.path}")

    async def _poll_folders(self):
        """Check for new files in all enabled watch folders."""
        async with async_session_factory() as session:
            result = await session.execute(
                select(WatchFolder).where(WatchFolder.is_enabled == True)
            )
            folders = result.scalars().all()

            for folder in folders:
                current_files = self._scan_directory(folder.path, folder.extensions)
                known = self._known_files.get(folder.id, set())
                new_files = current_files - known

                if new_files:
                    logger.info(f"Found {len(new_files)} new file(s) in {folder.path}")
                    for file_path in new_files:
                        # Check file age (delay_seconds) to avoid picking up partial writes
                        try:
                            mtime = os.path.getmtime(file_path)
                            age = datetime.utcnow().timestamp() - mtime
                            if age < (folder.delay_seconds or 30):
                                continue  # File too new, wait for next poll
                        except OSError:
                            continue

                        # Check not already queued
                        existing = await session.execute(
                            select(TranscodeJob).where(
                                TranscodeJob.source_path == file_path,
                                TranscodeJob.status.in_(["queued", "transcoding", "transferring"]),
                            )
                        )
                        if existing.scalar_one_or_none():
                            continue

                        job = TranscodeJob(
                            source_path=file_path,
                            status="queued",
                            preset_id=folder.preset_id,
                            priority=3,
                        )
                        session.add(job)
                        folder.files_processed = (folder.files_processed or 0) + 1
                        logger.info(f"Auto-queued: {file_path}")

                    folder.last_scan_at = datetime.utcnow()
                    await session.commit()

                    from app.api.websocket import manager
                    await manager.broadcast("folder_watch.new_files", {
                        "folder_id": folder.id,
                        "count": len(new_files),
                    })

                self._known_files[folder.id] = current_files

    @staticmethod
    def _scan_directory(path: str, extensions: str) -> Set[str]:
        """Scan directory using os.scandir (reliable over NFS/SMB)."""
        files = set()
        ext_list = [f".{e.strip()}" for e in extensions.split(",") if e.strip()]
        try:
            for entry in os.scandir(path):
                if entry.is_file() and any(entry.name.lower().endswith(ext) for ext in ext_list):
                    files.add(entry.path)
        except (OSError, PermissionError) as e:
            logger.debug(f"Cannot scan {path}: {e}")
        return files
