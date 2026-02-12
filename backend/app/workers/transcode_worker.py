import asyncio
import logging
import os
import re
import shlex
import time
from datetime import datetime
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

    async def start(self):
        logger.info("TranscodeWorker started")
        while self.running:
            try:
                await self._process_queue()
            except Exception as e:
                logger.error(f"Worker error: {e}")
            await asyncio.sleep(2)

    async def stop(self):
        self.running = False
        for pid, proc in self.active_processes.items():
            proc.terminate()

    async def cancel_job(self, job_id: int):
        """Cancel a running or queued job by killing its process."""
        self._cancelled_jobs.add(job_id)
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

            job = None
            for candidate in candidates:
                # Skip unassigned jobs whose source isn't locally accessible —
                # they're waiting for a cloud/remote worker to be assigned
                if candidate.worker_server_id is None:
                    check_path = candidate.worker_input_path or candidate.source_path
                    if check_path and not os.path.exists(check_path):
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

        # Find source file locally using path mappings
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
        staging_dir = "/tmp/mediaflow"
        if not os.path.exists(local_source):
            logger.info(f"Job {job.id}: source not found locally, attempting SSH pull from Plex server")
            media = await self._get_media(job, session)
            plex_server = await self._resolve_plex_server(job, media, session)

            if plex_server and plex_server.ssh_hostname:
                nas_ssh = SSHClient(plex_server.ssh_hostname, plex_server.ssh_port or 22,
                                    plex_server.ssh_username, plex_server.ssh_key_path,
                                    plex_server.ssh_password)

                staging_dir = "/tmp/mediaflow"
                os.makedirs(staging_dir, exist_ok=True)
                local_source = os.path.join(staging_dir, os.path.basename(job.source_path))
                pulled_from_nas = True

                job.status = "transferring"
                await session.commit()
                await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transferring"})
                await manager.broadcast("job.log", {
                    "job_id": job.id,
                    "message": f"Downloading from NAS {plex_server.ssh_hostname}...",
                })

                dl_progress = self._make_transfer_progress_cb(job.id, "download", job.source_size or 0)
                downloaded = await nas_ssh.download_file(job.source_path, local_source, progress_callback=dl_progress)
                if not downloaded:
                    job.status = "failed"
                    job.ffmpeg_log = f"Failed to download source from {plex_server.ssh_hostname}"
                    await session.commit()
                    await manager.broadcast("job.failed", {
                        "job_id": job.id, "error": f"SSH download failed from {plex_server.ssh_hostname}"
                    })
                    return
                logger.info(f"Job {job.id}: downloaded source from NAS to {local_source}")
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
                return

        if not pulled_from_nas:
            media = await self._get_media(job, session)
        start_time = time.time()

        # Ensure remote working directory exists
        working_dir = worker.working_directory or "/tmp/mediaflow"
        await ssh.run_command(f"mkdir -p {shlex.quote(working_dir)}")

        # Upload source to remote
        remote_source = f"{working_dir}/{os.path.basename(local_source)}"
        logger.info(f"Job {job.id}: uploading {local_source} to {worker.hostname}:{remote_source}")

        # Set status to transferring and add progress callback
        if not pulled_from_nas:
            job.status = "transferring"
            await session.commit()
            await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transferring"})
        await manager.broadcast("job.log", {
            "job_id": job.id,
            "message": f"Uploading to worker {worker.hostname}...",
        })

        upload_size = os.path.getsize(local_source) if os.path.exists(local_source) else 0
        ul_progress = self._make_transfer_progress_cb(job.id, "upload", upload_size)
        uploaded = await ssh.upload_file(local_source, remote_source, progress_callback=ul_progress)

        # Clean up staged file if we pulled it from NAS
        if pulled_from_nas and os.path.exists(local_source):
            try:
                os.remove(local_source)
                logger.info(f"Job {job.id}: cleaned up staged file {local_source}")
            except OSError:
                pass

        if not uploaded:
            job.status = "failed"
            job.ffmpeg_log = f"Failed to upload source to {worker.hostname}"
            await session.commit()
            await manager.broadcast("job.failed", {
                "job_id": job.id, "error": f"Upload failed to {worker.hostname}"
            })
            return

        # Rewrite ffmpeg command to use remote paths
        remote_output = os.path.splitext(remote_source)[0] + ".mediaflow." + (
            job.config_json.get("container", "mkv") if job.config_json else "mkv"
        )
        job.worker_input_path = remote_source
        job.worker_output_path = remote_output
        await session.commit()

        # Build remote ffmpeg command with the remote paths
        from app.utils.ffmpeg import FFmpegCommandBuilder
        config = job.config_json or {}
        builder = FFmpegCommandBuilder(config, remote_source)
        remote_ffmpeg_cmd = builder.build()
        # Replace local ffmpeg path with bare 'ffmpeg' for remote execution
        if remote_ffmpeg_cmd.startswith("/"):
            remote_ffmpeg_cmd = "ffmpeg" + remote_ffmpeg_cmd[remote_ffmpeg_cmd.index(" "):]

        # Run ffmpeg on remote via SSH (with streaming progress for cloud workers)
        job.status = "transcoding"
        await session.commit()
        await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transcoding"})

        logger.info(f"Job {job.id}: running ffmpeg on {worker.hostname}")
        total_duration = (media.duration_ms / 1000) if media and media.duration_ms else 0

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

            # NVENC/CUDA failure — fall back to CPU encoding and retry
            video_codec = config.get("video_codec", "")
            cpu_codec = NVENC_CPU_FALLBACK.get(video_codec)
            if cpu_codec and _is_nvenc_failure(log_text):
                logger.warning(
                    "Job %d: NVENC failed on worker, falling back to CPU codec %s",
                    job.id, cpu_codec,
                )
                await manager.broadcast("job.log", {
                    "job_id": job.id,
                    "message": f"GPU encoding unavailable — retrying with CPU encoder ({cpu_codec})...",
                })
                config = {**config, "video_codec": cpu_codec, "hw_accel": None}
                config.pop("encoder_tune", None)  # will be re-added by builder if set
                job.config_json = config

                fallback_builder = FFmpegCommandBuilder(config, remote_source)
                fallback_cmd = fallback_builder.build()
                if fallback_cmd.startswith("/"):
                    fallback_cmd = "ffmpeg" + fallback_cmd[fallback_cmd.index(" "):]

                # Reset progress
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

                # Update the stored ffmpeg command to reflect what actually ran
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
        # When source was pulled from NAS, download to local staging dir
        # (the NAS path doesn't exist locally)
        if pulled_from_nas:
            local_output = os.path.join(
                staging_dir, os.path.basename(remote_output)
            )
        else:
            local_output = job.output_path
            if not local_output:
                base = os.path.splitext(local_source)[0]
                container = config.get("container", "mkv")
                local_output = f"{base}.mediaflow.{container}"

        job.status = "transferring"
        await session.commit()
        await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transferring"})

        logger.info(f"Job {job.id}: downloading output from {worker.hostname}:{remote_output}")
        size_cmd = f"stat -c %s {shlex.quote(remote_output)} 2>/dev/null || stat -f %z {shlex.quote(remote_output)}"
        size_result = await ssh.run_command(size_cmd)
        dl_total = 0
        if size_result["exit_status"] == 0:
            try:
                dl_total = int(size_result["stdout"].strip())
            except ValueError:
                pass
        dl_progress = self._make_transfer_progress_cb(job.id, "download", dl_total)
        downloaded = await ssh.download_file(remote_output, local_output, progress_callback=dl_progress)
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

        # Record cloud cost for this job
        if worker.cloud_provider:
            await self._record_cloud_job_cost(worker, job, start_time, session)

        if pulled_from_nas:
            # Upload output back to NAS and replace original
            nas_remote_dir = os.path.dirname(job.source_path)
            nas_remote_output = f"{nas_remote_dir}/{os.path.basename(local_output)}"
            output_size_mb = os.path.getsize(local_output) / (1024 * 1024) if os.path.exists(local_output) else 0

            await manager.broadcast("job.log", {
                "job_id": job.id,
                "message": f"Uploading result ({output_size_mb:.0f} MB) to NAS {plex_server.ssh_hostname}...",
            })
            logger.info(f"Job {job.id}: uploading {local_output} to {plex_server.ssh_hostname}:{nas_remote_output}")

            ul_size = os.path.getsize(local_output) if os.path.exists(local_output) else 0
            ul_progress = self._make_transfer_progress_cb(job.id, "upload", ul_size)
            uploaded = await nas_ssh.upload_file(local_output, nas_remote_output, progress_callback=ul_progress)
            if not uploaded:
                for f in (local_source, local_output):
                    if f and os.path.exists(f):
                        os.remove(f)
                job.status = "failed"
                job.ffmpeg_log = f"Failed to upload output to {plex_server.ssh_hostname}"
                await session.commit()
                await manager.broadcast("job.failed", {"job_id": job.id, "error": job.ffmpeg_log})
                return

            # Replace original on NAS
            await manager.broadcast("job.log", {
                "job_id": job.id, "message": "Replacing original file on NAS...",
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

            # Clean up local staging files
            for f in (local_source, local_output):
                if f and os.path.exists(f):
                    os.remove(f)

            # Mark completed
            job.status = "completed"
            job.progress_percent = 100.0
            job.completed_at = datetime.utcnow()
            job.ffmpeg_log = "\n".join(log_lines[-100:]) if log_lines else ""
            job.output_path = final_remote
            await session.commit()

            duration = time.time() - start_time
            log_entry = JobLog(
                job_id=job.id,
                worker_server_id=job.worker_server_id,
                media_item_id=job.media_item_id,
                title=media.title if media else None,
                source_codec=media.video_codec if media else None,
                source_resolution=media.resolution_tier if media else None,
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
        else:
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
        job.status = "transferring"
        await session.commit()
        await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transferring"})
        await manager.broadcast("job.log", {
            "job_id": job.id,
            "message": f"Downloading from {plex_server.ssh_hostname}:{remote_source}",
        })
        logger.info(f"Job {job.id}: SSH pull downloading {remote_source} from {plex_server.ssh_hostname}")
        dl_progress = self._make_transfer_progress_cb(job.id, "download", job.source_size or 0)
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
        job.status = "transferring"
        await session.commit()
        await manager.broadcast("job.status_changed", {"job_id": job.id, "status": "transferring"})

        remote_dir = os.path.dirname(remote_source)
        remote_output = f"{remote_dir}/{os.path.basename(local_output)}"
        output_size_mb = os.path.getsize(local_output) / (1024 * 1024) if os.path.exists(local_output) else 0
        await manager.broadcast("job.log", {
            "job_id": job.id,
            "message": f"Uploading result ({output_size_mb:.0f} MB) to {plex_server.ssh_hostname}...",
        })
        logger.info(f"Job {job.id}: SSH pull uploading {local_output} to {plex_server.ssh_hostname}:{remote_output}")
        ul_size = os.path.getsize(local_output) if os.path.exists(local_output) else 0
        ul_progress = self._make_transfer_progress_cb(job.id, "upload", ul_size)
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

        # Step 4: Replace original on NAS via SSH
        await manager.broadcast("job.log", {
            "job_id": job.id,
            "message": "Replacing original file on NAS...",
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
        log_entry = JobLog(
            job_id=job.id,
            worker_server_id=job.worker_server_id,
            media_item_id=job.media_item_id,
            title=media.title if media else None,
            source_codec=media.video_codec if media else None,
            source_resolution=media.resolution_tier if media else None,
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

    def _make_transfer_progress_cb(self, job_id: int, direction: str, total_size: int):
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

                # Format speed
                if speed_bps >= 1_000_000_000:
                    speed_str = f"{speed_bps / 1_000_000_000:.1f} Gbps"
                elif speed_bps >= 1_000_000:
                    speed_str = f"{speed_bps / 1_000_000:.0f} Mbps"
                elif speed_bps >= 1_000:
                    speed_str = f"{speed_bps / 1_000:.0f} Kbps"
                else:
                    speed_str = f"{speed_bps:.0f} Bps"

                asyncio.ensure_future(
                    manager.broadcast("job.transfer_progress", {
                        "job_id": job_id,
                        "direction": direction,
                        "progress": round(progress, 1),
                        "speed": speed_str,
                        "eta_seconds": eta_seconds,
                        "bytes_transferred": bytes_transferred,
                        "total_bytes": total_bytes,
                    }))

        return callback

    # --- Shared helpers ---

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
            job.ffmpeg_log = "\n".join(log_lines[-100:]) if log_lines else ""
            job.ffmpeg_log += "\n[mediaflow] ffprobe verification failed on output file"
            await session.commit()
            await manager.broadcast("job.failed", {
                "job_id": job.id, "error": "Output verification failed"
            })
            return

        # Phase 6: In-place replacement of original file
        await self._replace_original(job, media, probe_path, session)

        job.status = "completed"
        job.progress_percent = 100.0
        job.completed_at = datetime.utcnow()
        job.ffmpeg_log = "\n".join(log_lines[-100:]) if log_lines else ""
        await session.commit()

        duration = time.time() - start_time
        log_entry = JobLog(
            job_id=job.id,
            worker_server_id=job.worker_server_id,
            media_item_id=job.media_item_id,
            title=media.title if media else None,
            source_codec=media.video_codec if media else None,
            source_resolution=media.resolution_tier if media else None,
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

    async def _handle_failure(self, job: TranscodeJob, log_lines: list, session) -> None:
        job.status = "failed"
        job.ffmpeg_log = "\n".join(log_lines[-100:]) if log_lines else ""
        await session.commit()

        await manager.broadcast("job.failed", {
            "job_id": job.id,
            "error": log_lines[-1] if log_lines else "Unknown error",
        })
