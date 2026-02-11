import asyncio
import json
import logging
from typing import Optional, Dict, Any

from app.config import settings

logger = logging.getLogger(__name__)


class MediaFileInfo:
    def __init__(self, data: Dict[str, Any]):
        self.raw = data
        self.format = data.get("format", {})
        self.streams = data.get("streams", [])

    @property
    def duration(self) -> float:
        return float(self.format.get("duration", 0))

    @property
    def size(self) -> int:
        return int(self.format.get("size", 0))

    @property
    def bitrate(self) -> int:
        return int(self.format.get("bit_rate", 0))

    @property
    def video_streams(self):
        return [s for s in self.streams if s.get("codec_type") == "video"]

    @property
    def audio_streams(self):
        return [s for s in self.streams if s.get("codec_type") == "audio"]

    @property
    def subtitle_streams(self):
        return [s for s in self.streams if s.get("codec_type") == "subtitle"]

    @property
    def video_codec(self) -> Optional[str]:
        vs = self.video_streams
        return vs[0].get("codec_name") if vs else None

    @property
    def width(self) -> Optional[int]:
        vs = self.video_streams
        return vs[0].get("width") if vs else None

    @property
    def height(self) -> Optional[int]:
        vs = self.video_streams
        return vs[0].get("height") if vs else None

    @property
    def frame_rate(self) -> Optional[float]:
        vs = self.video_streams
        if not vs:
            return None
        r_frame_rate = vs[0].get("r_frame_rate", "0/1")
        try:
            num, den = r_frame_rate.split("/")
            return round(float(num) / float(den), 3) if float(den) != 0 else None
        except (ValueError, ZeroDivisionError):
            return None

    @property
    def is_hdr(self) -> bool:
        vs = self.video_streams
        if not vs:
            return False
        color_transfer = vs[0].get("color_transfer", "")
        return color_transfer in ("smpte2084", "arib-std-b67")

    def to_dict(self) -> Dict[str, Any]:
        return {
            "duration": self.duration,
            "size": self.size,
            "bitrate": self.bitrate,
            "video_codec": self.video_codec,
            "width": self.width,
            "height": self.height,
            "frame_rate": self.frame_rate,
            "is_hdr": self.is_hdr,
            "audio_tracks": len(self.audio_streams),
            "subtitle_tracks": len(self.subtitle_streams),
        }


async def probe_file(file_path: str) -> Optional[MediaFileInfo]:
    try:
        cmd = [
            settings.FFPROBE_PATH,
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            file_path,
        ]
        process = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await process.communicate()

        if process.returncode != 0:
            logger.error(f"FFprobe failed: {stderr.decode()}")
            return None

        data = json.loads(stdout.decode())
        return MediaFileInfo(data)
    except Exception as e:
        logger.error(f"FFprobe error: {e}")
        return None
