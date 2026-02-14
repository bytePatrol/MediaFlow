import asyncio
import logging
import os
import re
import shlex
import time
from datetime import datetime, timedelta
from typing import Optional, List

from sqlalchemy import select

from app.database import async_session_factory
from app.models.transcode_job import TranscodeJob
from app.models.media_item import MediaItem
from app.models.worker_server import WorkerServer
from app.models.plex_library import PlexLibrary
from app.models.plex_server import PlexServer
from app.models.job_log import JobLog
from app.utils.ffprobe import probe_file
from app.utils.path_resolver import resolve_path
from app.api.websocket import manager

logger = logging.getLogger(__name__)

PROGRESS_PATTERN = re.compile(
    r"frame=\s*(\d+).*?fps=\s*([\d.]+).*?size=\s*(\d+\w+).*?time=(\d+:\d+:\d+\.\d+).*?speed=\s*([\d.]+)x"
)


NVENC_CPU_FALLBACK = {
    "hevc_nvenc": "libx265",
    "h264_nvenc": "libx264",
    "av1_nvenc": "libsvtav1",
}

NVENC_ERROR_PATTERNS = [
    "no CUDA-capable device",
    "CUDA_ERROR",
    "nvenc API version",
    "minimum required Nvidia driver",
    "Cannot load libcuda",
    "device type cuda needed",
]


def _is_nvenc_failure(log_text: str) -> bool:
    """Check if ffmpeg log indicates an NVENC/CUDA-specific failure."""
    return any(p in log_text for p in NVENC_ERROR_PATTERNS)


class TranscodeWorker:
    def __init__(self):
        self.running = True
        self.active_processes: dict = {}
        self._cancelled_jobs: set = set()
        self._preupload_task: Optional[asyncio.Task] = None
        self._preupload_job_id: Optional[int] = None

    async def start(self):
        logger.info("TranscodeWorker started")
        await self._recover_orphaned_jobs()
        while self.running:
            try:
                await self._process_queue()
            except Exception as e:
                logger.error(f"Worker error: {e}")
            await asyncio.sleep(2)

    async def stop(self):
        self.running = False
        if self._preupload_task and not self._preupload_task.done():
            self._preupload_task.cancel()
            self._preupload_task = None
            self._preupload_job_id = None
        for pid, proc in self.active_processes.items():
            proc.terminate()

    async def _recover_orphaned_jobs(self):
        """Re-queue jobs stuck in active states from a previous run."""
        async with async_session_factory() as session:
            result = await session.execute(
                select(TranscodeJob).where(
                    TranscodeJob.status.in_(["transcoding", "transferring", "verifying", "replacing"])
                )
            )
            orphans = result.scalars().all()
            for job in orphans:
                logger.info(f"Job {job.id}: recovering orphaned job (was {job.status}), re-queuing")
                job.status = "queued"
                job.status_detail = None
                job.progress_percent = 0.0
                job.current_fps = None
                job.eta_seconds = None
                job.source_prestaged = False

            # Also reset prestaged flag on any queued jobs (stale from previous run)
            prestaged_result = await session.execute(
                select(TranscodeJob).where(
                    TranscodeJob.status == "queued",
                    TranscodeJob.source_prestaged == True,  # noqa: E712
                )
            )
            for job in prestaged_result.scalars().all():
                logger.info(f"Job {job.id}: resetting stale source_prestaged flag")
                job.source_prestaged = False

            if orphans:
                await session.commit()
            else:
                await session.commit()
                logger.info("No orphaned jobs, checked prestaged flags")

    async def cancel_job(self, job_id: int):
        """Cancel a running or queued job by killing its process."""
        self._cancelled_jobs.add(job_id)
        # Cancel pre-upload if this job is being pre-uploaded
        if self._preupload_job_id == job_id and self._preupload_task and not self._preupload_task.done():
            logger.info(f"Job {job_id}: cancelling active pre-upload")
            self._preupload_task.cancel()
            self._preupload_task = None
            self._preupload_job_id = None
        proc = self.active_processes.get(job_id)
        if proc:
            logger.info(f"Job {job_id}: killing active process (pid={proc.pid})")
            try:
                proc.terminate()
            except ProcessLookupError:
                pass

    def is_cancelled(self, job_id: int) -> bool:
        return job_id in self._cancelled_jobs

    async def _process_queue(self):
        # Check schedule: if outside active hours, skip processing
        from app.workers.scheduler import is_within_active_hours
        if not await is_within_active_hours():
            return

        # Try to assign any unassigned queued jobs to available workers
        await self._try_assign_unassigned_jobs()

        async with async_session_factory() as session:
            result = await session.execute(
                select(TranscodeJob)
                .where(TranscodeJob.status == "queued")
                .order_by(TranscodeJob.priority.desc(), TranscodeJob.created_at.asc())
                .limit(10)
            )
            candidates = result.scalars().all()
            if not candidates:
                return

            now = datetime.utcnow()
            job = None
            for candidate in candidates:
                # Skip jobs that have a scheduled_after time in the future
                if candidate.scheduled_after is not None and candidate.scheduled_after > now:
                    continue
                # Skip unassigned jobs — they stay queued until a worker is
                # assigned (either by _try_assign_unassigned_jobs or cloud deploy)
                if candidate.worker_server_id is None:
                    continue
                job = candidate
                break

            if not job:
                return

            job.status = "transcoding"
            job.started_at = datetime.utcnow()
            await session.commit()

            await manager.broadcast("job.status_changed", {
                "job_id": job.id, "status": "transcoding"
            })

            await self._execute_job(job.id)

    async def _try_assign_unassigned_jobs(self):
        """Check for queued jobs with no worker and assign them if workers are available."""
        from app.services.transcode_service import TranscodeService
        from app.utils.ffmpeg import FFmpegCommandBuilder
        from app.utils.path_resolver import determine_transfer_mode

        async with async_session_factory() as session:
            # Find queued jobs with no worker assigned
            result = await session.execute(
                select(TranscodeJob).where(
                    TranscodeJob.status == "queued",
                    TranscodeJob.worker_server_id.is_(None),
                )
            )
            unassigned = result.scalars().all()
            if not unassigned:
                return

            # Check if any workers are available
            result = await session.execute(
                select(WorkerServer).where(
                    WorkerServer.is_enabled == True,  # noqa: E712
                    WorkerServer.status == "online",
                )
            )
            workers = result.scalars().all()
            if not workers:
                return

            svc = TranscodeService(session)

            for job in unassigned:
                # Determine if the Plex server has SSH configured (for Plex library jobs)
                plex_server_has_ssh = False
                if job.media_item_id:
                    media_result = await session.execute(
                        select(MediaItem).where(MediaItem.id == job.media_item_id)
                    )
                    media = media_result.scalar_one_or_none()
                    if media and media.plex_library_id:
                        lib_result = await session.execute(
                            select(PlexLibrary).where(PlexLibrary.id == media.plex_library_id)
                        )
                        lib = lib_result.scalar_one_or_none()
                        if lib and lib.plex_server_id:
                            srv_result = await session.execute(
                                select(PlexServer).where(PlexServer.id == lib.plex_server_id)
                            )
                            srv = srv_result.scalar_one_or_none()
                            if srv and srv.ssh_hostname:
                                plex_server_has_ssh = True

                # Assign to best available worker
                worker_id, mode, resolved_path = await svc._assign_worker(
                    job.source_path, plex_server_has_ssh=plex_server_has_ssh,
                )
                if not worker_id:
                    continue

                # Upgrade to NVENC if worker has GPU
                config = job.config_json or {}
                config = await svc._maybe_upgrade_to_nvenc(worker_id, config)

                # Rebuild ffmpeg command
                effective_input = resolved_path or job.source_path
                builder = FFmpegCommandBuilder(config, effective_input)
                ffmpeg_command = builder.build()

                # Determine output path — preserve V2 naming for manual jobs
                if job.media_item_id is None:
                    source_stem = os.path.splitext(os.path.basename(job.source_path))[0]
                    container = config.get("container", "mkv")
                    output_path = os.path.join(
                        os.path.dirname(effective_input),
                        f"{source_stem} V2.{container}",
                    )
                else:
                    output_path = builder._get_output_path()

                job.worker_server_id = worker_id
                job.transfer_mode = mode
                job.worker_input_path = resolved_path
                job.config_json = config
                job.ffmpeg_command = ffmpeg_command
                job.output_path = output_path

                logger.info(
                    f"Job {job.id}: assigned to worker {worker_id} (mode={mode})"
                )

            await session.commit()

    async def _execute_job(self, job_id: int):
        async with async_session_factory() as session:
            result = await session.execute(
                select(TranscodeJob).where(TranscodeJob.id == job_id)
            )
            job = result.scalar_one_or_none()
            if not job or not job.ffmpeg_command:
                return

            # Load assigned worker (if any)
            worker = None
            if job.worker_server_id:
                w_result = await session.execute(
                    select(WorkerServer).where(WorkerServer.id == job.worker_server_id)
                )
                worker = w_result.scalar_one_or_none()

            mode = job.transfer_mode or "local"

            # Check if already cancelled before starting
            if self.is_cancelled(job_id):
                job.status = "cancelled"
                await session.commit()
                self._cancelled_jobs.discard(job_id)
                await manager.broadcast("job.status_changed", {
                    "job_id": job.id, "status": "cancelled"
                })
                return

            try:
                if mode == "local" or mode == "mapped":
                    await self._execute_local(job, worker, session)
                elif mode == "ssh_pull":
                    await self._execute_ssh_pull(job, worker, session)
                elif mode == "ssh_transfer":
                    await self._execute_remote_transfer(job, worker, session)
                else:
                    await self._execute_local(job, worker, session)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.error(f"Job {job_id} failed: {e}")
                job.status = "failed"
                job.ffmpeg_log = str(e)
                await session.commit()
                self.active_processes.pop(job_id, None)
                await manager.broadcast("job.failed", {
                    "job_id": job.id, "error": str(e)
                })

    async def _execute_local(self, job: TranscodeJob, worker: Optional[WorkerServer],
                             session) -> None:
        """Execute ffmpeg as a local subprocess. Used for local and mapped modes."""
        check_path = job.worker_input_path or job.source_path
        if check_path and not os.path.exists(check_path):
            logger.error(f"Job {job.id}: source file not found: {check_path}")
            job.status = "failed"
            job.ffmpeg_log = f"Source file not accessible: {check_path}"
            await session.commit()
            await manager.broadcast("job.failed", {
                "job_id": job.id, "error": f"Source file not accessible: {check_path}"
            })
            return

        media = await self._get_media(job, session)
        total_duration = (media.duration_ms / 1000) if media and media.duration_ms else 0

        # For manual jobs (no media item), probe the source to get duration
        if total_duration == 0 and job.source_path:
            probe_info = await probe_file(job.source_path)
            if probe_info:
                total_duration = probe_info.duration

        start_time = time.time()

        process = await asyncio.create_subprocess_shell(
            job.ffmpeg_command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        self.active_processes[job.id] = process

        log_lines = await self._stream_progress(process, job, total_duration, session)

        await process.wait()
        self.active_processes.pop(job.id, None)

        # Check if job was cancelled during execution
        if self.is_cancelled(job.id):
            self._cancelled_jobs.discard(job.id)
            job.status = "cancelled"
            job.ffmpeg_log = "\n".join(log_lines[-50:]) if log_lines else ""
            await session.commit()
            logger.info(f"Job {job.id}: cancelled")
            await manager.broadcast("job.status_changed", {
                "job_id": job.id, "status": "cancelled"
            })
            return

        if process.returncode == 0:
            await self._handle_success(job, media, log_lines, start_time, session)
        else:
            await self._handle_failure(job, log_lines, session)

    async def _execute_remote_transfer(self, job: TranscodeJob,
                                       worker: Optional[WorkerServer], session) -> None:
        """No direct file access. Upload source via SCP, run ffmpeg via SSH, download output."""
        if not worker:
            job.status = "failed"
            job.ffmpeg_log = "No worker assigned for ssh_transfer mode"
            await session.commit()
            await manager.broadcast("job.failed", {
                "job_id": job.id, "error": "No worker assigned"
            })
            return

        from app.utils.ssh import SSHClient
        ssh = SSHClient(worker.hostname, worker.port,
                        worker.ssh_username, worker.ssh_key_path)

        # Resolve source file location
        resolved = await self._resolve_local_source(job, session)
        if resolved is None:
            return  # _resolve_local_source already set job to failed
        local_source, pulled_from_nas, nas_ssh, plex_server = resolved

        if not pulled_from_nas:
            media = await self._get_media(job, session)
        else:
            media = await self._get_media(job, session)
        start_time = time.time()

        # Ensure remote working directory exists
        working_dir = worker.working_directory or "/tmp/mediaflow"
        await ssh.run_command(f"mkdir -p {shlex.quote(working_dir)}")

        # Upload source to remote worker
        source_basename = os.path.basename(job.source_path if pulled_from_nas else local_source)
        remote_source = f"{working_dir}/{source_basename}"
        worker_label = f"remote GPU ({worker.name or worker.hostname})"

        # Check if source was pre-staged by a previous job's preupload
        upload_skipped = False
        if job.source_prestaged and job.worker_input_path:
            # Verify the pre-staged file actually exists on remote
            check = await ssh.run_command(f"test -f {shlex.quote(job.worker_input_path)} && echo ok")
            if check.get("stdout", "").strip() == "ok":
                logger.info(f"Job {job.id}: source already pre-staged at {job.worker_input_path}, skipping upload")
                remote_source = job.worker_input_path
                upload_skipped = True
                await manager.broadcast("job.log", {
                    "job_id": job.id,
                    "message": "Source already pre-staged — skipping upload",
                })
            else:
                logger.warning(f"Job {job.id}: pre-staged file missing at {job.worker_input_path}, falling back to normal upload")
                job.source_prestaged = False

        if not upload_skipped:
            job.status = "transferring"
            if pulled_from_nas:
                # Stream directly from Plex NAS to GPU worker (no local staging)
                relay_label = f"Transferring source from Plex NAS to {worker_label}"
                job.status_detail = f"{relay_label}..."
                await session.commit()
                await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transferring"})
                await manager.broadcast("job.log", {
                    "job_id": job.id,
                    "message": job.status_detail,
                })
                logger.info(f"Job {job.id}: relaying {job.source_path} from {plex_server.ssh_hostname} to {worker.hostname}:{remote_source}")

                relay_progress = self._make_transfer_progress_cb(job.id, "upload", job.source_size or 0, label=relay_label)
                uploaded = await nas_ssh.relay_to(
                    job.source_path, ssh, remote_source,
                    total_size=job.source_size or 0,
                    progress_callback=relay_progress,
                )
            else:
                # Upload from local filesystem
                job.status_detail = f"Uploading source to {worker_label}..."
                await session.commit()
                await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transferring"})
                await manager.broadcast("job.log", {
                    "job_id": job.id,
                    "message": job.status_detail,
                })
                logger.info(f"Job {job.id}: uploading {local_source} to {worker.hostname}:{remote_source}")

                upload_size = os.path.getsize(local_source) if os.path.exists(local_source) else 0
                ul_label = f"Uploading source to {worker_label}"
                ul_progress = self._make_transfer_progress_cb(job.id, "upload", upload_size, label=ul_label)
                uploaded = await ssh.upload_file(local_source, remote_source, progress_callback=ul_progress)

            if not uploaded:
                job.status = "failed"
                job.ffmpeg_log = f"Failed to transfer source to {worker.hostname}"
                await session.commit()
                await manager.broadcast("job.failed", {
                    "job_id": job.id, "error": f"Transfer failed to {worker.hostname}"
                })
                return

        # Rewrite ffmpeg command to use remote paths
        remote_output = os.path.splitext(remote_source)[0] + ".mediaflow." + (
            job.config_json.get("container", "mkv") if job.config_json else "mkv"
        )
        job.worker_input_path = remote_source
        job.worker_output_path = remote_output
        await session.commit()

        # Ensure NVENC upgrade is applied (may have been lost if backend reloaded mid-commit)
        from app.services.transcode_service import TranscodeService
        svc = TranscodeService(session)
        config = job.config_json or {}
        config = await svc._maybe_upgrade_to_nvenc(worker.id, config)
        job.config_json = config

        # Build remote ffmpeg command with the remote paths
        from app.utils.ffmpeg import FFmpegCommandBuilder
        builder = FFmpegCommandBuilder(config, remote_source)
        remote_ffmpeg_cmd = builder.build()
        # Replace local ffmpeg path with bare 'ffmpeg' for remote execution
        if remote_ffmpeg_cmd.startswith("/"):
            remote_ffmpeg_cmd = "ffmpeg" + remote_ffmpeg_cmd[remote_ffmpeg_cmd.index(" "):]

        # Run ffmpeg on remote via SSH (with streaming progress for cloud workers)
        job.status = "transcoding"
        job.status_detail = f"Transcoding on {worker_label}..."
        await session.commit()
        await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transcoding"})

        logger.info(f"Job {job.id}: running ffmpeg on {worker.hostname}")
        total_duration = (media.duration_ms / 1000) if media and media.duration_ms else 0

        # For manual jobs (no media item), probe the source to get duration
        if total_duration == 0 and job.source_path and os.path.exists(job.source_path):
            probe_info = await probe_file(job.source_path)
            if probe_info:
                total_duration = probe_info.duration

        # Start pre-uploading the next queued job while GPU transcodes
        await self._start_preupload_next_job(worker, ssh)

        if worker.cloud_provider:
            # Use streaming SSH for real-time progress on cloud workers
            async def _ffmpeg_line_cb(line: str):
                match = PROGRESS_PATTERN.search(line)
                if match and total_duration > 0:
                    frame = int(match.group(1))
                    fps = float(match.group(2))
                    time_str = match.group(4)
                    h, m, s = time_str.split(":")
                    current_seconds = int(h) * 3600 + int(m) * 60 + float(s)
                    progress = min(100.0, (current_seconds / total_duration) * 100)
                    eta = int((total_duration - current_seconds) / max(fps / 24, 0.01)) if fps > 0 else 0
                    job.progress_percent = round(progress, 1)
                    job.current_fps = fps
                    job.eta_seconds = eta
                    job.checkpoint_frame = frame
                    await session.commit()
                    await manager.broadcast("job.progress", {
                        "job_id": job.id, "progress": round(progress, 1),
                        "fps": fps, "eta_seconds": eta, "frame": frame,
                    })

            result = await ssh.run_command_streaming(remote_ffmpeg_cmd, line_callback=_ffmpeg_line_cb)
        else:
            result = await ssh.run_command(remote_ffmpeg_cmd)

        if result["exit_status"] != 0:
            log_text = result.get("stderr", "") or result.get("stdout", "")
            video_codec = config.get("video_codec", "")
            retried = False

            # Fallback 1: If CUDA hwaccel decode failed, retry with CPU decode + GPU encode
            if config.get("hw_accel") and video_codec in NVENC_CPU_FALLBACK:
                logger.warning(
                    "Job %d: CUDA hardware decode failed (exit %d), retrying with CPU decode + GPU encode",
                    job.id, result["exit_status"],
                )
                await manager.broadcast("job.log", {
                    "job_id": job.id,
                    "message": "CUDA decode failed — retrying with CPU decode + GPU encode...",
                })
                config = {**config, "hw_accel": None}
                job.config_json = config

                fb1_builder = FFmpegCommandBuilder(config, remote_source)
                fb1_cmd = fb1_builder.build()
                if fb1_cmd.startswith("/"):
                    fb1_cmd = "ffmpeg" + fb1_cmd[fb1_cmd.index(" "):]

                job.progress_percent = 0.0
                job.current_fps = None
                job.eta_seconds = None
                await session.commit()

                if worker.cloud_provider:
                    result = await ssh.run_command_streaming(fb1_cmd, line_callback=_ffmpeg_line_cb)
                else:
                    result = await ssh.run_command(fb1_cmd)

                if result["exit_status"] == 0:
                    job.ffmpeg_command = fb1_cmd
                    remote_output = os.path.splitext(remote_source)[0] + ".mediaflow." + (
                        config.get("container", "mkv")
                    )
                    retried = True
                else:
                    log_text = result.get("stderr", "") or result.get("stdout", "")

            # Fallback 2: NVENC encode failed — fall back to full CPU encoding
            if not retried and result["exit_status"] != 0:
                cpu_codec = NVENC_CPU_FALLBACK.get(video_codec)
                if cpu_codec and (_is_nvenc_failure(log_text)
                                  or video_codec in NVENC_CPU_FALLBACK):
                    logger.warning(
                        "Job %d: NVENC failed on worker, falling back to CPU codec %s",
                        job.id, cpu_codec,
                    )
                    await manager.broadcast("job.log", {
                        "job_id": job.id,
                        "message": f"GPU encoding unavailable — retrying with CPU encoder ({cpu_codec})...",
                    })
                    config = {**config, "video_codec": cpu_codec, "hw_accel": None}
                    config.pop("encoder_tune", None)
                    job.config_json = config

                    fallback_builder = FFmpegCommandBuilder(config, remote_source)
                    fallback_cmd = fallback_builder.build()
                    if fallback_cmd.startswith("/"):
                        fallback_cmd = "ffmpeg" + fallback_cmd[fallback_cmd.index(" "):]

                    job.progress_percent = 0.0
                    job.current_fps = None
                    job.eta_seconds = None
                    await session.commit()

                    if worker.cloud_provider:
                        result = await ssh.run_command_streaming(fallback_cmd, line_callback=_ffmpeg_line_cb)
                    else:
                        result = await ssh.run_command(fallback_cmd)

                    if result["exit_status"] != 0:
                        log_text = result.get("stderr", "") or result.get("stdout", "")
                        job.status = "failed"
                        job.ffmpeg_log = log_text[-5000:] if len(log_text) > 5000 else log_text
                        await session.commit()
                        await ssh.run_command(f"rm -f {shlex.quote(remote_source)} {shlex.quote(remote_output)}")
                        await manager.broadcast("job.failed", {
                            "job_id": job.id, "error": "Remote ffmpeg failed (CPU fallback)"
                        })
                        return

                    job.ffmpeg_command = fallback_cmd
                    remote_output = os.path.splitext(remote_source)[0] + ".mediaflow." + (
                        config.get("container", "mkv")
                    )
                else:
                    job.status = "failed"
                    job.ffmpeg_log = log_text[-5000:] if len(log_text) > 5000 else log_text
                    await session.commit()
                    await ssh.run_command(f"rm -f {shlex.quote(remote_source)} {shlex.quote(remote_output)}")
                    await manager.broadcast("job.failed", {
                        "job_id": job.id, "error": "Remote ffmpeg failed"
                    })
                    return

        # Download output from remote worker
        if pulled_from_nas:
            # Relay converted file directly from GPU to Plex NAS (no local staging)
            nas_remote_dir = os.path.dirname(job.source_path)
            nas_remote_output = f"{nas_remote_dir}/{os.path.basename(remote_output)}"

            relay_dl_label = f"Transferring converted file from {worker_label} to Plex NAS"
            job.status = "transferring"
            job.status_detail = f"{relay_dl_label}..."
            await session.commit()
            await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transferring"})
            await manager.broadcast("job.log", {
                "job_id": job.id,
                "message": job.status_detail,
            })

            logger.info(f"Job {job.id}: relaying output from {worker.hostname}:{remote_output} to {plex_server.ssh_hostname}:{nas_remote_output}")

            # Get remote output size for progress tracking
            size_cmd = f"stat -c %s {shlex.quote(remote_output)} 2>/dev/null || stat -f %z {shlex.quote(remote_output)}"
            size_result = await ssh.run_command(size_cmd)
            dl_total = 0
            if size_result["exit_status"] == 0:
                try:
                    dl_total = int(size_result["stdout"].strip())
                except ValueError:
                    pass

            relay_dl_progress = self._make_transfer_progress_cb(job.id, "download", dl_total, label=relay_dl_label)
            relayed = await ssh.relay_to(
                remote_output, nas_ssh, nas_remote_output,
                total_size=dl_total,
                progress_callback=relay_dl_progress,
            )
            if not relayed:
                job.status = "failed"
                job.ffmpeg_log = f"Failed to relay output from {worker.hostname} to {plex_server.ssh_hostname}"
                await session.commit()
                await manager.broadcast("job.failed", {"job_id": job.id, "error": job.ffmpeg_log})
                return

            # Cleanup remote temp files on GPU
            await ssh.run_command(f"rm -f {shlex.quote(remote_source)} {shlex.quote(remote_output)}")

            log_lines = (result.get("stderr", "") or "").split("\n")

            # Record cloud cost
            if worker.cloud_provider:
                await self._record_cloud_job_cost(worker, job, start_time, session)

            if job.media_item_id is not None:
                # Replace original on NAS
                job.status_detail = "Replacing original file on Plex NAS..."
                await session.commit()
                await manager.broadcast("job.log", {
                    "job_id": job.id, "message": job.status_detail,
                })
                backup_path = job.source_path + ".original"
                original_ext = os.path.splitext(job.source_path)[1]
                output_ext = os.path.splitext(nas_remote_output)[1]
                final_remote = (
                    os.path.splitext(job.source_path)[0] + output_ext
                    if original_ext != output_ext else job.source_path
                )

                rename_cmds = " && ".join([
                    f"mv {shlex.quote(job.source_path)} {shlex.quote(backup_path)}",
                    f"mv {shlex.quote(nas_remote_output)} {shlex.quote(final_remote)}",
                    f"rm -f {shlex.quote(backup_path)}",
                ])
                replace_result = await nas_ssh.run_command(rename_cmds)
                if replace_result["exit_status"] != 0:
                    logger.error(f"Job {job.id}: NAS replacement failed: {replace_result.get('stderr', '')}")
                    await nas_ssh.run_command(
                        f"test -f {shlex.quote(backup_path)} && mv {shlex.quote(backup_path)} {shlex.quote(job.source_path)}"
                    )

                # Get output size from NAS
                size_result = await nas_ssh.run_command(
                    f"stat -c %s {shlex.quote(final_remote)} 2>/dev/null || stat -f %z {shlex.quote(final_remote)}"
                )
                if size_result["exit_status"] == 0:
                    try:
                        job.output_size = int(size_result["stdout"].strip())
                    except ValueError:
                        pass

                # Update media item if extension changed
                if media and final_remote != job.source_path:
                    media.file_path = final_remote
                    media.file_size = job.output_size
                    await session.commit()
            else:
                # Manual job — output stays at the relayed path (no replacement)
                final_remote = nas_remote_output
                size_result = await nas_ssh.run_command(
                    f"stat -c %s {shlex.quote(final_remote)} 2>/dev/null || stat -f %z {shlex.quote(final_remote)}"
                )
                if size_result["exit_status"] == 0:
                    try:
                        job.output_size = int(size_result["stdout"].strip())
                    except ValueError:
                        pass

            # Mark completed
            job.status = "completed"
            job.status_detail = None
            job.progress_percent = 100.0
            job.completed_at = datetime.utcnow()
            job.ffmpeg_log = "\n".join(log_lines[-100:]) if log_lines else ""
            job.output_path = final_remote
            await session.commit()

            duration = time.time() - start_time
            _config = job.config_json or {}
            log_entry = JobLog(
                job_id=job.id,
                worker_server_id=job.worker_server_id,
                media_item_id=job.media_item_id,
                title=media.title if media else None,
                source_codec=media.video_codec if media else None,
                source_resolution=media.resolution_tier if media else None,
                target_codec=_config.get("video_codec"),
                target_resolution=_config.get("target_resolution"),
                source_size=job.source_size,
                target_size=job.output_size,
                size_reduction=round(1 - (job.output_size or 0) / max(job.source_size or 1, 1), 3),
                duration_seconds=round(duration, 1),
                avg_fps=job.current_fps,
                status="completed",
            )
            session.add(log_entry)
            await session.commit()

            await manager.broadcast("job.completed", {
                "job_id": job.id,
                "output_size": job.output_size,
                "duration": round(duration, 1),
            })

            await self._send_notification("job.completed", {
                "job_id": job.id,
                "output_size": job.output_size,
                "duration": round(duration, 1),
            })
        else:
            # Download to local filesystem
            local_output = job.output_path
            if not local_output:
                base = os.path.splitext(local_source)[0]
                container = config.get("container", "mkv")
                local_output = f"{base}.mediaflow.{container}"

            # For manual jobs (no media_item_id), ensure output goes to V2 path
            if job.media_item_id is None and local_output:
                source_dir = os.path.dirname(job.source_path)
                source_stem = os.path.splitext(os.path.basename(job.source_path))[0]
                container = (job.config_json or {}).get("container", "mkv")
                local_output = os.path.join(source_dir, f"{source_stem} V2.{container}")

            dl_label = f"Downloading converted file from {worker_label}"
            job.status = "transferring"
            job.status_detail = f"{dl_label}..."
            await session.commit()
            await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transferring"})

            logger.info(f"Job {job.id}: downloading output from {worker.hostname}:{remote_output}")
            await manager.broadcast("job.log", {
                "job_id": job.id,
                "message": job.status_detail,
            })
            size_cmd = f"stat -c %s {shlex.quote(remote_output)} 2>/dev/null || stat -f %z {shlex.quote(remote_output)}"
            size_result = await ssh.run_command(size_cmd)
            dl_total = 0
            if size_result["exit_status"] == 0:
                try:
                    dl_total = int(size_result["stdout"].strip())
                except ValueError:
                    pass
            dl_progress = self._make_transfer_progress_cb(job.id, "download", dl_total, label=dl_label)
            downloaded = await ssh.download_file(remote_output, local_output, progress_callback=dl_progress, total_size=dl_total)
            if not downloaded:
                job.status = "failed"
                job.ffmpeg_log = f"Failed to download output from {worker.hostname}"
                await session.commit()
                await manager.broadcast("job.failed", {
                    "job_id": job.id, "error": "Download failed"
                })
                return

            # Cleanup remote temp files
            await ssh.run_command(f"rm -f {shlex.quote(remote_source)} {shlex.quote(remote_output)}")

            log_lines = (result.get("stderr", "") or "").split("\n")

            # Record cloud cost
            if worker.cloud_provider:
                await self._record_cloud_job_cost(worker, job, start_time, session)

            # Local file — use standard success handler
            job.output_path = local_output
            await self._handle_success(job, media, log_lines, start_time, session)

    async def _execute_ssh_pull(self, job: TranscodeJob,
                               worker: Optional[WorkerServer], session) -> None:
        """Pull source from NAS via SSH, transcode locally, upload output back, replace original."""
        from app.utils.ssh import SSHClient
        from app.utils.ffmpeg import FFmpegCommandBuilder

        # Resolve Plex server SSH credentials via media_item → library → server
        media = await self._get_media(job, session)
        if not media or not media.plex_library_id:
            job.status = "failed"
            job.ffmpeg_log = "Cannot resolve Plex server for SSH pull — no media/library link"
            await session.commit()
            await manager.broadcast("job.failed", {"job_id": job.id, "error": job.ffmpeg_log})
            return

        lib_result = await session.execute(
            select(PlexLibrary).where(PlexLibrary.id == media.plex_library_id)
        )
        lib = lib_result.scalar_one_or_none()
        if not lib:
            job.status = "failed"
            job.ffmpeg_log = "Plex library not found for SSH pull"
            await session.commit()
            await manager.broadcast("job.failed", {"job_id": job.id, "error": job.ffmpeg_log})
            return

        srv_result = await session.execute(
            select(PlexServer).where(PlexServer.id == lib.plex_server_id)
        )
        plex_server = srv_result.scalar_one_or_none()
        if not plex_server or not plex_server.ssh_hostname:
            job.status = "failed"
            job.ffmpeg_log = "Plex server SSH not configured"
            await session.commit()
            await manager.broadcast("job.failed", {"job_id": job.id, "error": job.ffmpeg_log})
            return

        ssh = SSHClient(plex_server.ssh_hostname, plex_server.ssh_port or 22,
                        plex_server.ssh_username, plex_server.ssh_key_path,
                        plex_server.ssh_password)

        # Determine local working directory
        working_dir = (worker.working_directory if worker else None) or "/tmp/mediaflow"
        os.makedirs(working_dir, exist_ok=True)

        remote_source = job.source_path  # The Plex path IS the path on the NAS
        local_source = os.path.join(working_dir, os.path.basename(remote_source))

        # Step 1: Download source from NAS
        dl_label = f"Downloading source from Plex NAS ({plex_server.ssh_hostname})"
        job.status = "transferring"
        job.status_detail = f"{dl_label}..."
        await session.commit()
        await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transferring"})
        await manager.broadcast("job.log", {
            "job_id": job.id,
            "message": f"{dl_label}...",
        })
        logger.info(f"Job {job.id}: SSH pull downloading {remote_source} from {plex_server.ssh_hostname}")
        dl_progress = self._make_transfer_progress_cb(job.id, "download", job.source_size or 0, label=dl_label)
        downloaded = await ssh.download_file(remote_source, local_source, progress_callback=dl_progress)
        if not downloaded:
            job.status = "failed"
            job.ffmpeg_log = f"Failed to download {remote_source} from {plex_server.ssh_hostname}"
            await session.commit()
            await manager.broadcast("job.failed", {"job_id": job.id, "error": job.ffmpeg_log})
            return

        # Check cancellation after download
        if self.is_cancelled(job.id):
            self._cancelled_jobs.discard(job.id)
            job.status = "cancelled"
            await session.commit()
            for f in (local_source,):
                if os.path.exists(f):
                    os.remove(f)
            logger.info(f"Job {job.id}: cancelled after download")
            await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "cancelled"})
            return

        # Step 2: Build ffmpeg command with local paths and run locally
        source_size_mb = os.path.getsize(local_source) / (1024 * 1024)
        await manager.broadcast("job.log", {
            "job_id": job.id,
            "message": f"Download complete ({source_size_mb:.0f} MB). Starting transcode...",
        })

        job.status = "transcoding"
        job.status_detail = "Transcoding locally..."
        await session.commit()
        await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transcoding"})

        config = job.config_json or {}
        builder = FFmpegCommandBuilder(config, local_source)
        local_ffmpeg_cmd = builder.build()
        local_output = builder._get_output_path()

        total_duration = (media.duration_ms / 1000) if media.duration_ms else 0
        start_time = time.time()

        process = await asyncio.create_subprocess_shell(
            local_ffmpeg_cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        self.active_processes[job.id] = process

        log_lines = await self._stream_progress(process, job, total_duration, session)

        await process.wait()
        self.active_processes.pop(job.id, None)

        # Check cancellation after transcode
        if self.is_cancelled(job.id):
            self._cancelled_jobs.discard(job.id)
            job.status = "cancelled"
            job.ffmpeg_log = "\n".join(log_lines[-50:]) if log_lines else ""
            await session.commit()
            for f in (local_source, local_output):
                if f and os.path.exists(f):
                    os.remove(f)
            logger.info(f"Job {job.id}: cancelled during transcode")
            await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "cancelled"})
            return

        if process.returncode != 0:
            # Clean up local temp files
            for f in (local_source, local_output):
                if f and os.path.exists(f):
                    os.remove(f)
            await self._handle_failure(job, log_lines, session)
            return

        # Step 3: Upload transcoded output back to NAS
        remote_dir = os.path.dirname(remote_source)
        remote_output = f"{remote_dir}/{os.path.basename(local_output)}"
        output_size_mb = os.path.getsize(local_output) / (1024 * 1024) if os.path.exists(local_output) else 0
        ul_label = f"Uploading converted file to Plex NAS ({plex_server.ssh_hostname})"
        job.status = "transferring"
        job.status_detail = f"{ul_label} ({output_size_mb:.0f} MB)..."
        await session.commit()
        await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transferring"})
        await manager.broadcast("job.log", {
            "job_id": job.id,
            "message": f"{ul_label} ({output_size_mb:.0f} MB)...",
        })
        logger.info(f"Job {job.id}: SSH pull uploading {local_output} to {plex_server.ssh_hostname}:{remote_output}")
        ul_size = os.path.getsize(local_output) if os.path.exists(local_output) else 0
        ul_progress = self._make_transfer_progress_cb(job.id, "upload", ul_size, label=ul_label)
        uploaded = await ssh.upload_file(local_output, remote_output, progress_callback=ul_progress)
        if not uploaded:
            for f in (local_source, local_output):
                if f and os.path.exists(f):
                    os.remove(f)
            job.status = "failed"
            job.ffmpeg_log = f"Failed to upload output to {plex_server.ssh_hostname}"
            await session.commit()
            await manager.broadcast("job.failed", {"job_id": job.id, "error": job.ffmpeg_log})
            return

        # Step 4: Replace original on NAS via SSH (skip for manual jobs)
        if job.media_item_id is not None:
            job.status_detail = "Replacing original file on Plex NAS..."
            await session.commit()
            await manager.broadcast("job.log", {
                "job_id": job.id,
                "message": job.status_detail,
            })
            backup_path = remote_source + ".original"
            original_ext = os.path.splitext(remote_source)[1]
            output_ext = os.path.splitext(remote_output)[1]
            if original_ext != output_ext:
                final_remote = os.path.splitext(remote_source)[0] + output_ext
            else:
                final_remote = remote_source

            rename_cmds = " && ".join([
                f"mv {shlex.quote(remote_source)} {shlex.quote(backup_path)}",
                f"mv {shlex.quote(remote_output)} {shlex.quote(final_remote)}",
                f"rm -f {shlex.quote(backup_path)}",
            ])
            replace_result = await ssh.run_command(rename_cmds)
            if replace_result["exit_status"] != 0:
                logger.error(f"Job {job.id}: remote replacement failed: {replace_result.get('stderr', '')}")
                # Try to restore backup
                await ssh.run_command(
                    f"test -f {shlex.quote(backup_path)} && mv {shlex.quote(backup_path)} {shlex.quote(remote_source)}"
                )
        else:
            final_remote = remote_output

        # Step 5: Clean up local temp files
        for f in (local_source, local_output):
            if f and os.path.exists(f):
                os.remove(f)

        # Update media item if extension changed
        if media and final_remote != remote_source:
            media.file_path = final_remote
            media.file_size = job.output_size
            await session.commit()

        # Point job output_path to the final remote location for verification
        job.output_path = local_output  # Temporarily point to local for probe
        # Probe locally before cleanup — but we already cleaned up. Use log-only success.
        # Since we can't probe the remote file, mark success based on ffmpeg exit code.
        job.status = "completed"
        job.status_detail = None
        job.progress_percent = 100.0
        job.completed_at = datetime.utcnow()
        job.ffmpeg_log = "\n".join(log_lines[-100:]) if log_lines else ""
        job.output_path = final_remote

        # Get output size from the local file before it was cleaned — probe via SSH
        size_result = await ssh.run_command(f"stat -c %s {shlex.quote(final_remote)} 2>/dev/null || stat -f %z {shlex.quote(final_remote)}")
        if size_result["exit_status"] == 0:
            try:
                job.output_size = int(size_result["stdout"].strip())
            except ValueError:
                pass

        await session.commit()

        duration = time.time() - start_time
        _config = job.config_json or {}
        log_entry = JobLog(
            job_id=job.id,
            worker_server_id=job.worker_server_id,
            media_item_id=job.media_item_id,
            title=media.title if media else None,
            source_codec=media.video_codec if media else None,
            source_resolution=media.resolution_tier if media else None,
            target_codec=_config.get("video_codec"),
            target_resolution=_config.get("target_resolution"),
            source_size=job.source_size,
            target_size=job.output_size,
            size_reduction=round(1 - (job.output_size or 0) / max(job.source_size or 1, 1), 3),
            duration_seconds=round(duration, 1),
            avg_fps=job.current_fps,
            status="completed",
        )
        session.add(log_entry)
        await session.commit()

        await manager.broadcast("job.completed", {
            "job_id": job.id,
            "output_size": job.output_size,
            "duration": round(duration, 1),
        })

        await self._send_notification("job.completed", {
            "job_id": job.id,
            "output_size": job.output_size,
            "duration": round(duration, 1),
        })

    # --- Cloud cost helper ---

    async def _record_cloud_job_cost(self, worker: WorkerServer, job, start_time: float,
                                     session) -> None:
        """Record a CloudCostRecord for a job that ran on a cloud worker."""
        from app.models.cloud_cost import CloudCostRecord

        duration = time.time() - start_time
        hourly_rate = worker.hourly_cost or 0
        cost = round((duration / 3600) * hourly_rate, 4)

        record = CloudCostRecord(
            worker_server_id=worker.id,
            job_id=job.id,
            cloud_provider=worker.cloud_provider,
            cloud_instance_id=worker.cloud_instance_id,
            cloud_plan=worker.cloud_plan,
            hourly_rate=hourly_rate,
            start_time=datetime.utcfromtimestamp(start_time),
            end_time=datetime.utcnow(),
            duration_seconds=round(duration, 1),
            cost_usd=cost,
            record_type="job",
        )
        session.add(record)
        await session.commit()

    # --- Transfer progress helper ---

    def _make_transfer_progress_cb(self, job_id: int, direction: str, total_size: int,
                                    label: str = ""):
        """Create a progress callback for SFTP transfers that broadcasts via WebSocket."""
        start_time = time.time()
        last_broadcast = [0.0]  # mutable ref for closure

        def callback(src_path, dst_path, bytes_transferred, total_bytes):
            now = time.time()
            # Throttle broadcasts to ~every 0.5s
            if now - last_broadcast[0] < 0.5 and bytes_transferred < total_bytes:
                return
            last_broadcast[0] = now

            elapsed = now - start_time
            if elapsed > 0:
                speed_bps = bytes_transferred / elapsed
                remaining = total_bytes - bytes_transferred
                eta_seconds = int(remaining / speed_bps) if speed_bps > 0 else 0
                progress = (bytes_transferred / total_bytes * 100) if total_bytes > 0 else 0

                # Format speed (bytes/s → Mbps)
                speed_mbps = speed_bps * 8 / 1_000_000
                if speed_mbps >= 1000:
                    speed_str = f"{speed_mbps / 1000:.1f} Gbps"
                elif speed_mbps >= 1:
                    speed_str = f"{speed_mbps:.1f} Mbps"
                elif speed_mbps >= 0.001:
                    speed_str = f"{speed_mbps * 1000:.0f} Kbps"
                else:
                    speed_str = f"{speed_bps * 8:.0f} bps"

                asyncio.ensure_future(
                    manager.broadcast("job.transfer_progress", {
                        "job_id": job_id,
                        "direction": direction,
                        "label": label,
                        "progress": round(progress, 1),
                        "speed": speed_str,
                        "eta_seconds": eta_seconds,
                        "bytes_transferred": bytes_transferred,
                        "total_bytes": total_bytes,
                    }))

        return callback

    # --- Shared helpers ---

    async def _resolve_local_source(self, job: TranscodeJob, session):
        """Resolve the local source path for a job, trying path mappings and NAS SSH pull.

        Returns (local_source, pulled_from_nas, nas_ssh, plex_server) or None if failed.
        """
        from app.utils.ssh import SSHClient

        local_source = job.source_path

        # Try path mappings from the local (controller) worker first
        ctrl_result = await session.execute(
            select(WorkerServer).where(WorkerServer.is_local == True)  # noqa: E712
        )
        controller = ctrl_result.scalar_one_or_none()
        if controller and controller.path_mappings:
            resolved = resolve_path(job.source_path, controller.path_mappings)
            if resolved:
                local_source = resolved

        # Also try app-level path mappings from settings
        if not os.path.exists(local_source):
            from app.models.app_settings import AppSetting
            result = await session.execute(
                select(AppSetting).where(AppSetting.key == "path_mappings")
            )
            setting = result.scalar_one_or_none()
            if setting and setting.value:
                import json as _json
                try:
                    mappings = _json.loads(setting.value)
                    resolved = resolve_path(job.source_path, mappings)
                    if resolved:
                        local_source = resolved
                except Exception:
                    pass

        # If file not found locally, try pulling from Plex server via SSH
        pulled_from_nas = False
        nas_ssh = None
        plex_server = None
        if not os.path.exists(local_source):
            logger.info(f"Job {job.id}: source not found locally, attempting SSH pull from Plex server")
            media = await self._get_media(job, session)
            plex_server = await self._resolve_plex_server(job, media, session)

            if plex_server and plex_server.ssh_hostname:
                nas_ssh = SSHClient(plex_server.ssh_hostname, plex_server.ssh_port or 22,
                                    plex_server.ssh_username, plex_server.ssh_key_path,
                                    plex_server.ssh_password)
                pulled_from_nas = True
            else:
                job.status = "failed"
                job.ffmpeg_log = (
                    f"Source file not accessible locally for upload: {local_source}\n"
                    "Configure SSH on the Plex server or set up path mappings."
                )
                await session.commit()
                await manager.broadcast("job.failed", {
                    "job_id": job.id, "error": f"Source not found: {local_source}"
                })
                return None

        return (local_source, pulled_from_nas, nas_ssh, plex_server)

    async def _start_preupload_next_job(self, worker: WorkerServer, ssh) -> None:
        """Check for a next queued job on the same worker and start pre-uploading its source."""
        # Cancel any existing preupload first
        if self._preupload_task and not self._preupload_task.done():
            self._preupload_task.cancel()
            self._preupload_task = None
            self._preupload_job_id = None

        async with async_session_factory() as session:
            result = await session.execute(
                select(TranscodeJob).where(
                    TranscodeJob.status == "queued",
                    TranscodeJob.worker_server_id == worker.id,
                    TranscodeJob.transfer_mode == "ssh_transfer",
                    TranscodeJob.source_prestaged == False,  # noqa: E712
                ).order_by(TranscodeJob.priority.desc(), TranscodeJob.created_at.asc())
                .limit(1)
            )
            next_job = result.scalar_one_or_none()
            if not next_job:
                return

            logger.info(f"Job {next_job.id}: starting pre-upload while GPU is busy (worker={worker.id})")
            self._preupload_job_id = next_job.id
            self._preupload_task = asyncio.create_task(
                self._preupload_source(next_job.id, worker)
            )

    async def _preupload_source(self, job_id: int, worker: WorkerServer) -> None:
        """Background task: upload the next job's source to the worker while GPU transcodes."""
        from app.utils.ssh import SSHClient

        try:
            async with async_session_factory() as session:
                result = await session.execute(
                    select(TranscodeJob).where(TranscodeJob.id == job_id)
                )
                job = result.scalar_one_or_none()
                if not job or job.status != "queued":
                    return

                # Resolve source path
                resolved = await self._resolve_local_source(job, session)
                if resolved is None:
                    return
                local_source, pulled_from_nas, nas_ssh, plex_server = resolved

                # Determine remote path
                working_dir = worker.working_directory or "/tmp/mediaflow"
                source_basename = os.path.basename(job.source_path if pulled_from_nas else local_source)
                remote_source = f"{working_dir}/{source_basename}"

                # Create a fresh SSH connection for the preupload (don't share with ffmpeg)
                preupload_ssh = SSHClient(worker.hostname, worker.port,
                                          worker.ssh_username, worker.ssh_key_path)
                await preupload_ssh.run_command(f"mkdir -p {shlex.quote(working_dir)}")

                worker_label = f"remote GPU ({worker.name or worker.hostname})"

                await manager.broadcast("job.preupload_started", {
                    "job_id": job_id,
                })

                if pulled_from_nas:
                    logger.info(f"Job {job_id}: pre-uploading via NAS relay to {worker.hostname}")
                    preupload_progress = self._make_preupload_progress_cb(
                        job_id, job.source_size or 0, f"Pre-uploading to {worker_label}"
                    )
                    uploaded = await nas_ssh.relay_to(
                        job.source_path, preupload_ssh, remote_source,
                        total_size=job.source_size or 0,
                        progress_callback=preupload_progress,
                    )
                else:
                    logger.info(f"Job {job_id}: pre-uploading {local_source} to {worker.hostname}")
                    upload_size = os.path.getsize(local_source) if os.path.exists(local_source) else 0
                    preupload_progress = self._make_preupload_progress_cb(
                        job_id, upload_size, f"Pre-uploading to {worker_label}"
                    )
                    uploaded = await preupload_ssh.upload_file(
                        local_source, remote_source, progress_callback=preupload_progress
                    )

                if uploaded:
                    job.source_prestaged = True
                    job.worker_input_path = remote_source
                    await session.commit()
                    logger.info(f"Job {job_id}: pre-upload complete, source staged at {remote_source}")
                    await manager.broadcast("job.preupload_completed", {
                        "job_id": job_id,
                    })
                else:
                    logger.warning(f"Job {job_id}: pre-upload failed, will upload normally when job runs")

        except asyncio.CancelledError:
            logger.info(f"Job {job_id}: pre-upload cancelled")
            # Try to clean up the partial remote file (only this job's file, not others)
            try:
                from app.utils.ssh import SSHClient
                cleanup_ssh = SSHClient(worker.hostname, worker.port,
                                        worker.ssh_username, worker.ssh_key_path)
                working_dir = worker.working_directory or "/tmp/mediaflow"
                # Look up source path from DB to find what to clean
                async with async_session_factory() as cs:
                    r = await cs.execute(select(TranscodeJob).where(TranscodeJob.id == job_id))
                    cj = r.scalar_one_or_none()
                    source_basename = os.path.basename(cj.source_path) if cj and cj.source_path else ""
                if source_basename:
                    await cleanup_ssh.run_command(
                        f"rm -f {shlex.quote(working_dir + '/' + source_basename)}"
                    )
            except Exception:
                pass
            # Reset prestaged flag
            try:
                async with async_session_factory() as cleanup_session:
                    result = await cleanup_session.execute(
                        select(TranscodeJob).where(TranscodeJob.id == job_id)
                    )
                    j = result.scalar_one_or_none()
                    if j:
                        j.source_prestaged = False
                        await cleanup_session.commit()
            except Exception:
                pass
            raise
        except Exception as e:
            logger.warning(f"Job {job_id}: pre-upload error: {e}")
        finally:
            if self._preupload_job_id == job_id:
                self._preupload_task = None
                self._preupload_job_id = None

    def _make_preupload_progress_cb(self, job_id: int, total_size: int, label: str = ""):
        """Create a progress callback for pre-upload that broadcasts via WebSocket."""
        start_time = time.time()
        last_broadcast = [0.0]

        def callback(src_path, dst_path, bytes_transferred, total_bytes):
            now = time.time()
            if now - last_broadcast[0] < 0.5 and bytes_transferred < total_bytes:
                return
            last_broadcast[0] = now

            elapsed = now - start_time
            if elapsed > 0:
                speed_bps = bytes_transferred / elapsed
                remaining = total_bytes - bytes_transferred
                eta_seconds = int(remaining / speed_bps) if speed_bps > 0 else 0
                progress = (bytes_transferred / total_bytes * 100) if total_bytes > 0 else 0

                speed_mbps = speed_bps * 8 / 1_000_000
                if speed_mbps >= 1000:
                    speed_str = f"{speed_mbps / 1000:.1f} Gbps"
                elif speed_mbps >= 1:
                    speed_str = f"{speed_mbps:.1f} Mbps"
                elif speed_mbps >= 0.001:
                    speed_str = f"{speed_mbps * 1000:.0f} Kbps"
                else:
                    speed_str = f"{speed_bps * 8:.0f} bps"

                asyncio.ensure_future(
                    manager.broadcast("job.preupload_progress", {
                        "job_id": job_id,
                        "label": label,
                        "progress": round(progress, 1),
                        "speed": speed_str,
                        "eta_seconds": eta_seconds,
                        "bytes_transferred": bytes_transferred,
                        "total_bytes": total_bytes,
                    }))

        return callback

    async def _resolve_plex_server(self, job: TranscodeJob, media, session):
        """Resolve the Plex server with SSH credentials for a job's media item."""
        if not media or not media.plex_library_id:
            return None
        lib_result = await session.execute(
            select(PlexLibrary).where(PlexLibrary.id == media.plex_library_id)
        )
        lib = lib_result.scalar_one_or_none()
        if not lib:
            return None
        srv_result = await session.execute(
            select(PlexServer).where(PlexServer.id == lib.plex_server_id)
        )
        return srv_result.scalar_one_or_none()

    async def _get_media(self, job: TranscodeJob, session) -> Optional[MediaItem]:
        if not job.media_item_id:
            return None
        result = await session.execute(
            select(MediaItem).where(MediaItem.id == job.media_item_id)
        )
        return result.scalar_one_or_none()

    async def _stream_progress(self, process, job: TranscodeJob,
                               total_duration: float, session) -> List[str]:
        """Read ffmpeg stderr, parse progress lines, broadcast updates. Returns log lines.

        ffmpeg writes progress lines with \\r (carriage return), not \\n.
        We read raw chunks and split on both \\r and \\n to capture progress.
        """
        log_lines = []
        buffer = b""
        while True:
            chunk = await process.stderr.read(4096)
            if not chunk:
                break
            buffer += chunk
            # Split on \r or \n
            while b"\r" in buffer or b"\n" in buffer:
                # Find the earliest delimiter
                r_pos = buffer.find(b"\r")
                n_pos = buffer.find(b"\n")
                if r_pos == -1:
                    pos = n_pos
                elif n_pos == -1:
                    pos = r_pos
                else:
                    pos = min(r_pos, n_pos)

                line_bytes = buffer[:pos]
                # Skip past delimiter (and \r\n pair)
                if pos + 1 < len(buffer) and buffer[pos:pos+2] == b"\r\n":
                    buffer = buffer[pos+2:]
                else:
                    buffer = buffer[pos+1:]

                line_text = line_bytes.decode("utf-8", errors="replace").strip()
                if not line_text:
                    continue
                log_lines.append(line_text)

                match = PROGRESS_PATTERN.search(line_text)
                if match and total_duration > 0:
                    frame = int(match.group(1))
                    fps = float(match.group(2))
                    time_str = match.group(4)

                    h, m, s = time_str.split(":")
                    current_seconds = int(h) * 3600 + int(m) * 60 + float(s)
                    progress = min(100.0, (current_seconds / total_duration) * 100)
                    eta = int((total_duration - current_seconds) / max(fps / 24, 0.01)) if fps > 0 else 0

                    job.progress_percent = round(progress, 1)
                    job.current_fps = fps
                    job.eta_seconds = eta
                    job.checkpoint_frame = frame
                    await session.commit()

                    await manager.broadcast("job.progress", {
                        "job_id": job.id,
                        "progress": round(progress, 1),
                        "fps": fps,
                        "eta_seconds": eta,
                        "frame": frame,
                    })

        # Process any remaining buffer
        if buffer:
            line_text = buffer.decode("utf-8", errors="replace").strip()
            if line_text:
                log_lines.append(line_text)
        return log_lines

    async def _handle_success(self, job: TranscodeJob, media: Optional[MediaItem],
                              log_lines: list, start_time: float, session) -> None:
        job.status = "verifying"
        await session.commit()

        # Determine which output path to probe
        probe_path = job.output_path
        if not probe_path and job.ffmpeg_command:
            # Extract output path from ffmpeg command (last argument)
            parts = shlex.split(job.ffmpeg_command)
            if parts:
                probe_path = parts[-1]
                job.output_path = probe_path

        output_info = await probe_file(probe_path) if probe_path else None
        if output_info:
            job.output_size = output_info.size
        else:
            # Verification failed — output file missing or corrupt
            logger.error(f"Job {job.id}: ffprobe verification failed for {probe_path}")
            job.status = "failed"
            job.validation_status = "failed"
            job.ffmpeg_log = "\n".join(log_lines[-100:]) if log_lines else ""
            job.ffmpeg_log += "\n[mediaflow] ffprobe verification failed on output file"
            await session.commit()
            await manager.broadcast("job.failed", {
                "job_id": job.id, "error": "Output verification failed"
            })
            return

        # Post-transcode quality validation
        source_duration = (media.duration_ms / 1000) if media and media.duration_ms else None
        validation_passed = await self._validate_output(job, probe_path, output_info, source_duration, session)
        if not validation_passed:
            job.ffmpeg_log = "\n".join(log_lines[-100:]) if log_lines else ""
            await self._handle_failure(job, log_lines, session)
            return

        # Phase 6: In-place replacement of original file (skip for manual jobs)
        if job.media_item_id is not None:
            await self._replace_original(job, media, probe_path, session)

        job.status = "completed"
        job.progress_percent = 100.0
        job.completed_at = datetime.utcnow()
        job.ffmpeg_log = "\n".join(log_lines[-100:]) if log_lines else ""
        await session.commit()

        duration = time.time() - start_time
        _config = job.config_json or {}
        log_entry = JobLog(
            job_id=job.id,
            worker_server_id=job.worker_server_id,
            media_item_id=job.media_item_id,
            title=media.title if media else None,
            source_codec=media.video_codec if media else None,
            source_resolution=media.resolution_tier if media else None,
            target_codec=_config.get("video_codec"),
            target_resolution=_config.get("target_resolution"),
            source_size=job.source_size,
            target_size=job.output_size,
            size_reduction=round(1 - (job.output_size or 0) / max(job.source_size or 1, 1), 3),
            duration_seconds=round(duration, 1),
            avg_fps=job.current_fps,
            status="completed",
        )
        session.add(log_entry)
        await session.commit()

        await manager.broadcast("job.completed", {
            "job_id": job.id,
            "output_size": job.output_size,
            "duration": round(duration, 1),
        })

        await self._send_notification("job.completed", {
            "job_id": job.id,
            "output_size": job.output_size,
            "duration": round(duration, 1),
        })

    async def _validate_output(self, job: TranscodeJob, output_path: str,
                               output_info, source_duration: Optional[float],
                               session) -> bool:
        """Validate the transcoded output file. Returns True if validation passes."""
        try:
            # Check 1: Output file must exist and be probed
            if not output_info:
                job.validation_status = "failed"
                job.status_detail = "Validation failed: output file could not be probed"
                logger.error(f"Job {job.id}: validation failed — no probe info")
                await session.commit()
                return False

            # Check 2: Must have a valid video stream
            has_video = getattr(output_info, 'video_codec', None) is not None
            if not has_video:
                job.validation_status = "failed"
                job.status_detail = "Validation failed: no video stream in output"
                logger.error(f"Job {job.id}: validation failed — no video stream")
                await session.commit()
                return False

            # Check 3: File size must be > 1MB (catch corrupt/empty output)
            output_size = getattr(output_info, 'size', 0) or 0
            if output_size < 1_048_576:  # 1 MB
                job.validation_status = "failed"
                job.status_detail = f"Validation failed: output too small ({output_size} bytes)"
                logger.error(f"Job {job.id}: validation failed — output only {output_size} bytes")
                await session.commit()
                return False

            # Check 4: Duration matches source (within 2 second tolerance)
            output_duration = getattr(output_info, 'duration', 0) or 0
            if source_duration and source_duration > 0 and output_duration > 0:
                duration_diff = abs(output_duration - source_duration)
                if duration_diff > 2.0:
                    job.validation_status = "failed"
                    job.status_detail = (
                        f"Validation failed: duration mismatch "
                        f"(source={source_duration:.1f}s, output={output_duration:.1f}s, "
                        f"diff={duration_diff:.1f}s)"
                    )
                    logger.error(f"Job {job.id}: validation failed — duration mismatch by {duration_diff:.1f}s")
                    await session.commit()
                    return False

            # All checks passed
            job.validation_status = "passed"
            await session.commit()
            logger.info(f"Job {job.id}: validation passed")
            return True

        except Exception as e:
            logger.error(f"Job {job.id}: validation error: {e}")
            job.validation_status = "failed"
            job.status_detail = f"Validation error: {e}"
            await session.commit()
            return False

    async def _replace_original(self, job: TranscodeJob, media: Optional[MediaItem],
                                output_path: str, session) -> None:
        """Replace the original file with the transcoded output after verification."""
        if not output_path or not os.path.exists(output_path):
            return

        # Determine the original file path (use worker_input_path for mapped paths)
        original_path = job.worker_input_path or job.source_path
        if not original_path or not os.path.exists(original_path):
            logger.warning(f"Job {job.id}: original not found for replacement: {original_path}")
            return

        job.status = "replacing"
        await session.commit()
        await manager.broadcast("job.status_changed", {
            "job_id": job.id, "status": "replacing"
        })

        backup_path = original_path + ".original"
        original_ext = os.path.splitext(original_path)[1]
        output_ext = os.path.splitext(output_path)[1]

        try:
            # Rename original to backup
            os.rename(original_path, backup_path)

            # If container changed, the final file gets the new extension at the original's location
            if original_ext != output_ext:
                final_path = os.path.splitext(original_path)[0] + output_ext
            else:
                final_path = original_path

            # Move output to original's location
            os.rename(output_path, final_path)

            # Remove backup
            os.remove(backup_path)

            # Update media item file_path if extension changed
            if media and final_path != original_path:
                media.file_path = self._plex_path_from_local(
                    final_path, job.source_path, original_path
                )
                media.file_size = job.output_size
                await session.commit()

            # Update job output path to final location
            job.output_path = final_path
            logger.info(f"Job {job.id}: replaced original at {final_path}")

        except Exception as e:
            logger.error(f"Job {job.id}: in-place replacement failed: {e}")
            # Attempt to restore backup
            if os.path.exists(backup_path) and not os.path.exists(original_path):
                try:
                    os.rename(backup_path, original_path)
                except Exception:
                    logger.error(f"Job {job.id}: failed to restore backup!")

    @staticmethod
    def _plex_path_from_local(local_final: str, plex_source: str, local_original: str) -> str:
        """Reconstruct the Plex-style path from a local final path.

        If the extension changed, we need to update the Plex path too.
        """
        original_ext = os.path.splitext(plex_source)[1]
        new_ext = os.path.splitext(local_final)[1]
        if original_ext != new_ext:
            return os.path.splitext(plex_source)[0] + new_ext
        return plex_source

    async def _send_notification(self, event: str, data: dict):
        """Fire-and-forget notification dispatch in a separate session."""
        try:
            async with async_session_factory() as notify_session:
                from app.services.notification_service import NotificationService
                svc = NotificationService(notify_session)
                await svc.send_notification(event, data)
        except Exception as e:
            logger.error(f"Notification send error: {e}")

    async def _handle_failure(self, job: TranscodeJob, log_lines: list, session) -> None:
        job.status = "failed"
        job.ffmpeg_log = "\n".join(log_lines[-100:]) if log_lines else ""
        await session.commit()

        await manager.broadcast("job.failed", {
            "job_id": job.id,
            "error": log_lines[-1] if log_lines else "Unknown error",
        })

        await self._send_notification("job.failed", {
            "job_id": job.id,
            "error": log_lines[-1] if log_lines else "Unknown error",
        })

        # Auto-retry logic
        if (job.retry_count or 0) < (job.max_retries or 3):
            job.retry_count = (job.retry_count or 0) + 1
            backoff_minutes = [1, 5, 15][min(job.retry_count - 1, 2)]
            job.status = "queued"
            job.scheduled_after = datetime.utcnow() + timedelta(minutes=backoff_minutes)
            job.progress_percent = 0.0
            job.current_fps = None
            job.eta_seconds = None
            job.worker_server_id = None
            logger.info(f"Job {job.id} scheduled for retry #{job.retry_count} in {backoff_minutes}m")
            await session.commit()
            await manager.broadcast("job.retry_scheduled", {
                "job_id": job.id,
                "retry_count": job.retry_count,
                "max_retries": job.max_retries or 3,
                "backoff_minutes": backoff_minutes,
            })
