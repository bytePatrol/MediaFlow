from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from app.database import get_session
from app.models.job_log import JobLog
from app.models.transcode_job import TranscodeJob
from app.models.media_item import MediaItem
from app.utils.ffprobe import probe_file
from app.config import settings
import asyncio
import base64
import logging
import os

router = APIRouter(prefix="/comparison", tags=["comparison"])
logger = logging.getLogger(__name__)

THUMBNAIL_CACHE_DIR = "/tmp/mediaflow/thumbnails"


async def _get_duration(file_path: str) -> float:
    """Get video duration in seconds using ffprobe."""
    info = await probe_file(file_path)
    if info and info.duration > 0:
        return info.duration
    return 0.0


async def _generate_thumbnails(file_path: str, output_dir: str, prefix: str, count: int = 10) -> list[str]:
    """Generate thumbnail images at regular intervals from a video file.

    Returns a list of file paths of generated thumbnails.
    """
    os.makedirs(output_dir, exist_ok=True)

    duration = await _get_duration(file_path)
    if duration <= 0:
        raise HTTPException(status_code=400, detail=f"Could not determine duration of {file_path}")

    # Calculate frame interval: we want `count` thumbnails evenly spaced
    # Use ffprobe to get total frame count, then select every N-th frame
    # Simpler approach: use timestamps
    timestamps = []
    for i in range(count):
        t = duration * (i + 0.5) / count  # center of each segment
        timestamps.append(t)

    output_pattern = os.path.join(output_dir, f"{prefix}_%02d.jpg")

    # Build a select filter using timestamps
    select_expr = "+".join([f"between(t\\,{t-0.5}\\,{t+0.5})" for t in timestamps])

    cmd = [
        settings.FFMPEG_PATH,
        "-y",
        "-i", file_path,
        "-vf", f"select='{select_expr}',scale=480:-1",
        "-vsync", "vfn",
        "-frames:v", str(count),
        "-q:v", "3",
        output_pattern,
    ]

    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    _, stderr = await process.communicate()

    if process.returncode != 0:
        logger.warning(f"FFmpeg thumbnail generation returned {process.returncode}: {stderr.decode()[:500]}")

    # Collect generated files
    generated = []
    for i in range(1, count + 1):
        path = os.path.join(output_dir, f"{prefix}_{i:02d}.jpg")
        if os.path.exists(path):
            generated.append(path)

    return generated


def _format_timestamp(seconds: float) -> str:
    """Format seconds to HH:MM:SS."""
    h = int(seconds) // 3600
    m = (int(seconds) % 3600) // 60
    s = int(seconds) % 60
    return f"{h:02d}:{m:02d}:{s:02d}"


@router.get("/{job_id}/thumbnails")
async def get_comparison_thumbnails(
    job_id: int,
    count: int = 10,
    session: AsyncSession = Depends(get_session),
):
    """Generate and return thumbnail strip pairs for original and transcoded files."""
    # Look up the job
    result = await session.execute(select(TranscodeJob).where(TranscodeJob.id == job_id))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    if job.status != "completed":
        raise HTTPException(status_code=400, detail="Job must be completed to generate comparison thumbnails")

    source_path = job.source_path
    output_path = job.output_path

    if not source_path or not output_path:
        raise HTTPException(status_code=400, detail="Source or output path not available")

    # Check if files exist
    if not os.path.exists(source_path):
        raise HTTPException(status_code=400, detail=f"Source file not found: {source_path}")
    if not os.path.exists(output_path):
        raise HTTPException(status_code=400, detail=f"Output file not found: {output_path}")

    # Cache directory
    cache_dir = os.path.join(THUMBNAIL_CACHE_DIR, str(job_id))
    original_dir = os.path.join(cache_dir, "original")
    transcoded_dir = os.path.join(cache_dir, "transcoded")

    # Check if cached thumbnails exist
    original_cached = os.path.exists(original_dir) and len(
        [f for f in os.listdir(original_dir) if f.endswith(".jpg")]
    ) >= count
    transcoded_cached = os.path.exists(transcoded_dir) and len(
        [f for f in os.listdir(transcoded_dir) if f.endswith(".jpg")]
    ) >= count

    # Generate thumbnails if not cached
    if not original_cached:
        original_files = await _generate_thumbnails(source_path, original_dir, "orig", count)
    else:
        original_files = sorted(
            [os.path.join(original_dir, f) for f in os.listdir(original_dir) if f.endswith(".jpg")]
        )[:count]

    if not transcoded_cached:
        transcoded_files = await _generate_thumbnails(output_path, transcoded_dir, "trans", count)
    else:
        transcoded_files = sorted(
            [os.path.join(transcoded_dir, f) for f in os.listdir(transcoded_dir) if f.endswith(".jpg")]
        )[:count]

    if not original_files and not transcoded_files:
        raise HTTPException(status_code=500, detail="Failed to generate any thumbnails")

    # Get duration for timestamp calculation
    duration = await _get_duration(source_path)

    # Build paired response
    thumbnails = []
    pair_count = min(len(original_files), len(transcoded_files))
    for i in range(pair_count):
        timestamp_sec = duration * (i + 0.5) / count if duration > 0 else 0

        # Read and base64-encode images
        with open(original_files[i], "rb") as f:
            original_b64 = base64.b64encode(f.read()).decode("utf-8")
        with open(transcoded_files[i], "rb") as f:
            transcoded_b64 = base64.b64encode(f.read()).decode("utf-8")

        thumbnails.append({
            "timestamp": _format_timestamp(timestamp_sec),
            "original": original_b64,
            "transcoded": transcoded_b64,
        })

    return {"thumbnails": thumbnails}


@router.get("/{job_id}/metadata")
async def get_comparison_metadata(
    job_id: int,
    session: AsyncSession = Depends(get_session),
):
    """Get before/after metadata for a completed transcode job."""
    # Look up the job
    result = await session.execute(select(TranscodeJob).where(TranscodeJob.id == job_id))
    job = result.scalar_one_or_none()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    # Look up the job log for codec info
    log_result = await session.execute(
        select(JobLog).where(JobLog.job_id == job_id).order_by(JobLog.id.desc()).limit(1)
    )
    job_log = log_result.scalar_one_or_none()

    # Look up the media item for additional info
    media_item = None
    if job.media_item_id:
        mi_result = await session.execute(
            select(MediaItem).where(MediaItem.id == job.media_item_id)
        )
        media_item = mi_result.scalar_one_or_none()

    # Build metadata
    source_codec = None
    source_resolution = None
    source_bitrate = None
    target_codec = None
    target_resolution = None
    target_bitrate = None
    vmaf_score = None
    size_reduction = None

    if job_log:
        source_codec = job_log.source_codec
        source_resolution = job_log.source_resolution
        target_codec = job_log.target_codec
        target_resolution = job_log.target_resolution
        vmaf_score = job_log.vmaf_score
        size_reduction = job_log.size_reduction

    # Fallback to media item data
    if not source_codec and media_item:
        source_codec = media_item.video_codec
    if not source_resolution and media_item:
        if media_item.width and media_item.height:
            source_resolution = f"{media_item.width}x{media_item.height}"
    if not source_bitrate and media_item:
        source_bitrate = media_item.video_bitrate

    # Try to get bitrate from ffprobe if files exist
    source_size = job.source_size or (job_log.source_size if job_log else None)
    target_size = job.output_size or (job_log.target_size if job_log else None)

    return {
        "job_id": job_id,
        "source_codec": source_codec,
        "source_resolution": source_resolution,
        "source_size": source_size,
        "source_bitrate": source_bitrate,
        "target_codec": target_codec,
        "target_resolution": target_resolution,
        "target_size": target_size,
        "target_bitrate": target_bitrate,
        "vmaf_score": vmaf_score,
        "size_reduction": size_reduction,
    }
