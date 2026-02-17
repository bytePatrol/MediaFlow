import logging
import asyncio
import os
import re
import json
from typing import Optional, Tuple

from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, func

from app.models.job_log import JobLog
from app.models.transcode_job import TranscodeJob

logger = logging.getLogger(__name__)


class VMAFService:
    def __init__(self, session: AsyncSession):
        self.session = session

    async def compute_vmaf(self, job_id: int) -> Optional[float]:
        """Run VMAF comparison between source and output files for a completed job."""
        result = await self.session.execute(
            select(TranscodeJob).where(TranscodeJob.id == job_id)
        )
        job = result.scalar_one_or_none()
        if not job or job.status != "completed":
            return None

        source_path = job.source_path
        output_path = job.output_path

        if not source_path or not output_path:
            return None

        if not os.path.exists(source_path) or not os.path.exists(output_path):
            logger.warning(f"VMAF: Source or output file missing for job {job_id}")
            return None

        try:
            vmaf_score = await self._run_vmaf_ffmpeg(source_path, output_path)

            if vmaf_score is not None:
                # Update job log
                log_result = await self.session.execute(
                    select(JobLog).where(JobLog.job_id == job_id).order_by(JobLog.id.desc()).limit(1)
                )
                job_log = log_result.scalar_one_or_none()
                if job_log:
                    job_log.vmaf_score = vmaf_score
                    job_log.vmaf_model = "vmaf_v0.6.1"
                    await self.session.commit()

                logger.info(f"VMAF score for job {job_id}: {vmaf_score}")

            return vmaf_score

        except Exception as e:
            logger.error(f"VMAF computation failed for job {job_id}: {e}")
            return None

    async def _run_vmaf_ffmpeg(self, reference: str, distorted: str) -> Optional[float]:
        """Run ffmpeg with libvmaf filter and parse the score."""
        cmd = [
            "ffmpeg", "-i", distorted, "-i", reference,
            "-lavfi", "libvmaf=model=version=vmaf_v0.6.1:log_fmt=json:log_path=/dev/stdout",
            "-f", "null", "-"
        ]

        try:
            process = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(
                process.communicate(), timeout=3600  # 1 hour max
            )

            # Parse VMAF score from JSON output
            output = stdout.decode("utf-8", errors="replace")

            # Try to find the pooled_metrics in JSON output
            try:
                vmaf_data = json.loads(output)
                if "pooled_metrics" in vmaf_data:
                    return round(vmaf_data["pooled_metrics"]["vmaf"]["mean"], 2)
            except json.JSONDecodeError:
                pass

            # Fallback: parse from stderr (ffmpeg logs)
            stderr_text = stderr.decode("utf-8", errors="replace")
            for line in stderr_text.split("\n"):
                if "VMAF score" in line:
                    parts = line.split("VMAF score")[-1]
                    for token in parts.split():
                        try:
                            return round(float(token), 2)
                        except ValueError:
                            continue

            # Another fallback: look for "score: XX.XX" pattern
            match = re.search(r'(?:vmaf|VMAF).*?(\d+\.?\d*)', stderr_text)
            if match:
                return round(float(match.group(1)), 2)

            logger.warning("Could not parse VMAF score from output")
            return None

        except asyncio.TimeoutError:
            logger.error("VMAF computation timed out after 1 hour")
            return None
        except FileNotFoundError:
            logger.error("ffmpeg not found for VMAF computation")
            return None

    @staticmethod
    def quality_label(score: Optional[float]) -> str:
        """Human-readable quality label for VMAF score."""
        if score is None:
            return "Unknown"
        if score >= 95:
            return "Excellent"
        if score >= 90:
            return "Great"
        if score >= 80:
            return "Good"
        if score >= 70:
            return "Fair"
        return "Poor"

    async def get_quality_stats(self):
        """Aggregate VMAF stats across all completed jobs."""
        result = await self.session.execute(
            select(
                func.count(),
                func.avg(JobLog.vmaf_score),
                func.min(JobLog.vmaf_score),
                func.max(JobLog.vmaf_score),
            ).where(
                JobLog.vmaf_score.isnot(None),
            )
        )
        row = result.first()

        # By codec pair
        codec_result = await self.session.execute(
            select(
                JobLog.source_codec,
                JobLog.target_codec,
                func.count(),
                func.avg(JobLog.vmaf_score),
            ).where(
                JobLog.vmaf_score.isnot(None),
                JobLog.source_codec.isnot(None),
                JobLog.target_codec.isnot(None),
            ).group_by(JobLog.source_codec, JobLog.target_codec)
        )
        by_codec = [
            {
                "source_codec": r[0],
                "target_codec": r[1],
                "jobs": r[2],
                "avg_vmaf": round(r[3], 1) if r[3] else None,
            }
            for r in codec_result.all()
        ]

        return {
            "total_scored": row[0] or 0,
            "avg_score": round(row[1], 1) if row[1] else None,
            "min_score": round(row[2], 1) if row[2] else None,
            "max_score": round(row[3], 1) if row[3] else None,
            "by_codec": by_codec,
        }
