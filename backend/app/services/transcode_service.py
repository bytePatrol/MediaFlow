import logging
from typing import Optional, List, Dict, Any, Tuple

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.models.transcode_job import TranscodeJob
from app.models.transcode_preset import TranscodePreset
from app.models.media_item import MediaItem
from app.models.worker_server import WorkerServer
from app.models.plex_library import PlexLibrary
from app.models.plex_server import PlexServer
from app.schemas.transcode import (
    TranscodeJobCreate, TranscodeJobResponse, TranscodeJobUpdate,
    QueueStatsResponse, DryRunResponse,
)
from app.utils.ffmpeg import FFmpegCommandBuilder
from app.utils.path_resolver import determine_transfer_mode

logger = logging.getLogger(__name__)


class TranscodeService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def _assign_worker(self, plex_path: str,
                             plex_server_has_ssh: bool = False,
                             preferred_worker_id: Optional[int] = None) -> Tuple[Optional[int], str, Optional[str]]:
        """Pick the best available worker for a file path using composite scoring.

        Returns (worker_server_id, transfer_mode, worker_input_path).
        Scoring: transfer_cost (35%) + perf_cost (30%) + load_cost (35%).
        """
        # If preferred worker specified, try to use it
        if preferred_worker_id:
            pref_result = await self.session.execute(
                select(WorkerServer).where(
                    WorkerServer.id == preferred_worker_id,
                    WorkerServer.is_enabled == True,  # noqa: E712
                    WorkerServer.status == "online",
                )
            )
            pref_worker = pref_result.scalar_one_or_none()
            if pref_worker:
                mode, resolved = determine_transfer_mode(
                    plex_path, pref_worker.is_local, pref_worker.path_mappings or [],
                    plex_server_has_ssh=plex_server_has_ssh,
                )
                return (pref_worker.id, mode, resolved)

        result = await self.session.execute(
            select(WorkerServer).where(
                WorkerServer.is_enabled == True,  # noqa: E712
                WorkerServer.status == "online",
            )
        )
        workers = result.scalars().all()
        if not workers:
            return (None, "local", plex_path)

        # Count active jobs per worker
        active_counts = {}
        for w in workers:
            count_result = await self.session.execute(
                select(func.count()).select_from(TranscodeJob).where(
                    TranscodeJob.worker_server_id == w.id,
                    TranscodeJob.status.in_(["transcoding", "verifying", "replacing"]),
                )
            )
            active_counts[w.id] = count_result.scalar() or 0

        # Composite scoring: lower is better
        TRANSFER_COST = {"local": 0, "mapped": 25, "ssh_pull": 50, "ssh_transfer": 75}

        def compute_score(w, mode, include_capacity_check=True):
            if include_capacity_check and active_counts[w.id] >= w.max_concurrent_jobs:
                return None
            transfer_cost = TRANSFER_COST.get(mode, 100)
            perf_cost = 100 - (w.performance_score if w.performance_score is not None else 50)
            load_cost = (active_counts[w.id] / max(w.max_concurrent_jobs, 1)) * 100
            return transfer_cost * 0.35 + perf_cost * 0.30 + load_cost * 0.35

        candidates = []
        for w in workers:
            mode, resolved = determine_transfer_mode(
                plex_path, w.is_local, w.path_mappings or [],
                plex_server_has_ssh=plex_server_has_ssh,
            )
            score = compute_score(w, mode)
            if score is not None:
                candidates.append((score, w.id, mode, resolved))

        if not candidates:
            # All workers busy — assign to the best worker anyway (will queue)
            for w in workers:
                mode, resolved = determine_transfer_mode(
                    plex_path, w.is_local, w.path_mappings or [],
                    plex_server_has_ssh=plex_server_has_ssh,
                )
                score = compute_score(w, mode, include_capacity_check=False)
                if score is not None:
                    candidates.append((score, w.id, mode, resolved))

        candidates.sort(key=lambda c: c[0])
        _, worker_id, mode, resolved_path = candidates[0]
        return (worker_id, mode, resolved_path)

    async def create_jobs(self, request: TranscodeJobCreate) -> List[TranscodeJob]:
        preset = None
        if request.preset_id:
            result = await self.session.execute(
                select(TranscodePreset).where(TranscodePreset.id == request.preset_id)
            )
            preset = result.scalar_one_or_none()

        config = request.config or {}
        if preset:
            config = {
                "video_codec": preset.video_codec,
                "target_resolution": preset.target_resolution,
                "bitrate_mode": preset.bitrate_mode,
                "crf_value": preset.crf_value,
                "target_bitrate": preset.target_bitrate,
                "hw_accel": preset.hw_accel,
                "audio_mode": preset.audio_mode,
                "audio_codec": preset.audio_codec,
                "container": preset.container,
                "subtitle_mode": preset.subtitle_mode,
                "custom_flags": preset.custom_flags,
                "hdr_mode": preset.hdr_mode,
                "two_pass": preset.two_pass,
                "encoder_tune": preset.encoder_tune,
                **config,
            }

        jobs = []
        for media_id in request.media_item_ids:
            result = await self.session.execute(
                select(MediaItem).where(MediaItem.id == media_id)
            )
            media = result.scalar_one_or_none()
            if not media:
                continue

            # Check if the Plex server has SSH configured (media → library → server)
            plex_server_has_ssh = False
            if media.plex_library_id:
                lib_result = await self.session.execute(
                    select(PlexLibrary).where(PlexLibrary.id == media.plex_library_id)
                )
                lib = lib_result.scalar_one_or_none()
                if lib and lib.plex_server_id:
                    srv_result = await self.session.execute(
                        select(PlexServer).where(PlexServer.id == lib.plex_server_id)
                    )
                    srv = srv_result.scalar_one_or_none()
                    if srv and srv.ssh_hostname:
                        plex_server_has_ssh = True

            worker_id, transfer_mode, worker_input_path = await self._assign_worker(
                media.file_path,
                plex_server_has_ssh=plex_server_has_ssh,
                preferred_worker_id=request.preferred_worker_id,
            )

            # Build ffmpeg command using the resolved worker path
            effective_input = worker_input_path or media.file_path
            builder = FFmpegCommandBuilder(config, effective_input)
            ffmpeg_command = builder.build()
            output_path = builder._get_output_path()

            job = TranscodeJob(
                media_item_id=media_id,
                preset_id=request.preset_id,
                config_json=config,
                status="queued",
                priority=request.priority,
                source_path=media.file_path,
                source_size=media.file_size,
                is_dry_run=request.is_dry_run,
                scheduled_after=request.scheduled_after,
                worker_server_id=worker_id,
                transfer_mode=transfer_mode,
                worker_input_path=worker_input_path,
                output_path=output_path,
                ffmpeg_command=ffmpeg_command,
            )

            self.session.add(job)
            jobs.append(job)

        await self.session.commit()
        for job in jobs:
            await self.session.refresh(job)
        return jobs

    async def get_jobs(self, status: Optional[str] = None,
                       page: int = 1, page_size: int = 50) -> Dict[str, Any]:
        query = select(TranscodeJob)
        if status:
            statuses = [s.strip() for s in status.split(",")]
            query = query.where(TranscodeJob.status.in_(statuses))

        count_query = select(func.count()).select_from(query.subquery())
        total_result = await self.session.execute(count_query)
        total = total_result.scalar() or 0

        query = query.order_by(TranscodeJob.priority.desc(), TranscodeJob.created_at.asc())
        offset = (page - 1) * page_size
        query = query.offset(offset).limit(page_size)

        result = await self.session.execute(query)
        jobs = result.scalars().all()

        job_responses = []
        for job in jobs:
            resp = TranscodeJobResponse.model_validate(job)
            if job.media_item_id:
                media_result = await self.session.execute(
                    select(MediaItem.title).where(MediaItem.id == job.media_item_id)
                )
                resp.media_title = media_result.scalar_one_or_none()
            job_responses.append(resp)

        return {
            "items": [r.model_dump() for r in job_responses],
            "total": total,
            "page": page,
            "page_size": page_size,
        }

    async def get_job(self, job_id: int) -> Optional[TranscodeJobResponse]:
        result = await self.session.execute(
            select(TranscodeJob).where(TranscodeJob.id == job_id)
        )
        job = result.scalar_one_or_none()
        if not job:
            return None
        resp = TranscodeJobResponse.model_validate(job)
        if job.media_item_id:
            media_result = await self.session.execute(
                select(MediaItem.title).where(MediaItem.id == job.media_item_id)
            )
            resp.media_title = media_result.scalar_one_or_none()
        return resp

    async def update_job(self, job_id: int, update: TranscodeJobUpdate) -> Optional[TranscodeJob]:
        result = await self.session.execute(
            select(TranscodeJob).where(TranscodeJob.id == job_id)
        )
        job = result.scalar_one_or_none()
        if not job:
            return None

        for key, value in update.model_dump(exclude_unset=True).items():
            setattr(job, key, value)
        await self.session.commit()
        await self.session.refresh(job)
        return job

    async def clear_finished_jobs(self) -> int:
        """Delete all completed, failed, and cancelled jobs."""
        result = await self.session.execute(
            select(TranscodeJob).where(
                TranscodeJob.status.in_(["completed", "failed", "cancelled"])
            )
        )
        jobs = result.scalars().all()
        count = len(jobs)
        for job in jobs:
            await self.session.delete(job)
        await self.session.commit()
        return count

    async def get_queue_stats(self) -> QueueStatsResponse:
        statuses = ["queued", "transcoding", "completed", "failed"]
        counts = {}
        for status in statuses:
            result = await self.session.execute(
                select(func.count()).select_from(TranscodeJob)
                .where(TranscodeJob.status == status)
            )
            counts[status] = result.scalar() or 0

        active_result = await self.session.execute(
            select(TranscodeJob).where(TranscodeJob.status == "transcoding")
        )
        active_jobs = active_result.scalars().all()
        aggregate_fps = sum(j.current_fps or 0 for j in active_jobs)
        total_eta = sum(j.eta_seconds or 0 for j in active_jobs)

        return QueueStatsResponse(
            total_queued=counts["queued"],
            total_active=len(active_jobs),
            total_completed=counts["completed"],
            total_failed=counts["failed"],
            aggregate_fps=aggregate_fps,
            estimated_total_time=total_eta,
        )

    async def dry_run(self, media_item_id: int, preset_id: Optional[int] = None,
                      config: Optional[dict] = None) -> DryRunResponse:
        result = await self.session.execute(
            select(MediaItem).where(MediaItem.id == media_item_id)
        )
        media = result.scalar_one_or_none()
        if not media:
            raise ValueError("Media item not found")

        final_config = config or {}
        if preset_id:
            preset_result = await self.session.execute(
                select(TranscodePreset).where(TranscodePreset.id == preset_id)
            )
            preset = preset_result.scalar_one_or_none()
            if preset:
                final_config = {
                    "video_codec": preset.video_codec,
                    "target_resolution": preset.target_resolution,
                    "bitrate_mode": preset.bitrate_mode,
                    "crf_value": preset.crf_value,
                    "target_bitrate": preset.target_bitrate,
                    "container": preset.container,
                    **final_config,
                }

        builder = FFmpegCommandBuilder(final_config, media.file_path)
        command = builder.build()

        estimated_reduction = 0.5
        estimated_output = int((media.file_size or 0) * (1 - estimated_reduction))

        return DryRunResponse(
            ffmpeg_command=command,
            estimated_output_size=estimated_output,
            estimated_duration=None,
            estimated_reduction_percent=estimated_reduction * 100,
        )
