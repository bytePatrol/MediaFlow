import os
import shlex
from typing import Optional, Dict, Any, List

from app.config import settings

RESOLUTION_MAP = {
    "4K": "3840:2160",
    "2160p": "3840:2160",
    "1080p": "1920:1080",
    "720p": "1280:720",
    "480p": "854:480",
    "SD": "640:480",
}

CODEC_MAP = {
    "libx265": {"encoder": "libx265", "pix_fmt": "yuv420p10le"},
    "libx264": {"encoder": "libx264", "pix_fmt": "yuv420p"},
    "libsvtav1": {"encoder": "libsvtav1", "pix_fmt": "yuv420p10le"},
    "hevc_nvenc": {"encoder": "hevc_nvenc", "pix_fmt": "p010le"},
    "h264_nvenc": {"encoder": "h264_nvenc", "pix_fmt": "yuv420p"},
    "hevc_videotoolbox": {"encoder": "hevc_videotoolbox", "pix_fmt": "nv12"},
    "h264_videotoolbox": {"encoder": "h264_videotoolbox", "pix_fmt": "nv12"},
    "hevc_qsv": {"encoder": "hevc_qsv", "pix_fmt": "nv12"},
    "av1_nvenc": {"encoder": "av1_nvenc", "pix_fmt": "p010le"},
}

HW_ACCEL_INPUT = {
    "nvenc": ["-hwaccel", "cuda", "-hwaccel_output_format", "cuda"],
    "videotoolbox": ["-hwaccel", "videotoolbox"],
    "qsv": ["-hwaccel", "qsv"],
}


class FFmpegCommandBuilder:
    def __init__(self, config: Dict[str, Any], input_path: str):
        self.config = config
        self.input_path = input_path
        self.ffmpeg_path = settings.FFMPEG_PATH

    def build(self) -> str:
        parts = [self.ffmpeg_path, "-y"]

        hw_accel = self.config.get("hw_accel")
        if hw_accel and hw_accel in HW_ACCEL_INPUT:
            parts.extend(HW_ACCEL_INPUT[hw_accel])

        parts.extend(["-i", shlex.quote(self.input_path)])

        parts.extend(self._build_video_args())
        parts.extend(self._build_audio_args())
        parts.extend(self._build_subtitle_args())

        custom_flags = self.config.get("custom_flags")
        if custom_flags:
            parts.extend(shlex.split(custom_flags))

        output_path = self._get_output_path()
        parts.append(shlex.quote(output_path))

        return " ".join(parts)

    def _build_video_args(self) -> List[str]:
        args = []
        codec_key = self.config.get("video_codec", "libx265")
        codec_info = CODEC_MAP.get(codec_key, {"encoder": codec_key, "pix_fmt": "yuv420p"})

        args.extend(["-c:v", codec_info["encoder"]])

        hdr_mode = self.config.get("hdr_mode", "preserve")
        if hdr_mode == "tonemap":
            args.extend(["-vf", "zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709:t=bt709:m=bt709:r=tv,format=yuv420p"])
            args.extend(["-pix_fmt", "yuv420p"])
        else:
            args.extend(["-pix_fmt", codec_info["pix_fmt"]])

        target_res = self.config.get("target_resolution")
        if target_res and target_res in RESOLUTION_MAP:
            scale = RESOLUTION_MAP[target_res]
            if hdr_mode != "tonemap":
                args.extend(["-vf", f"scale={scale}:flags=lanczos"])
            else:
                current_vf = next((args[i+1] for i, a in enumerate(args) if a == "-vf"), "")
                if current_vf:
                    idx = args.index(current_vf)
                    args[idx] = f"{current_vf},scale={scale}:flags=lanczos"

        bitrate_mode = self.config.get("bitrate_mode", "crf")
        if bitrate_mode == "crf":
            crf = self.config.get("crf_value", 23)
            args.extend(["-crf", str(crf)])
        elif bitrate_mode == "cbr":
            bitrate = self.config.get("target_bitrate", "8M")
            args.extend(["-b:v", bitrate, "-maxrate", bitrate, "-bufsize", f"{int(bitrate.rstrip('MmKk')) * 2}M"])
        elif bitrate_mode == "vbr":
            bitrate = self.config.get("target_bitrate", "8M")
            args.extend(["-b:v", bitrate])

        tune = self.config.get("encoder_tune")
        if tune:
            args.extend(["-tune", tune])

        two_pass = self.config.get("two_pass", False)
        if two_pass and "nvenc" not in codec_key:
            pass

        return args

    def _build_audio_args(self) -> List[str]:
        args = []
        audio_mode = self.config.get("audio_mode", "copy")

        if audio_mode == "copy":
            args.extend(["-c:a", "copy"])
        elif audio_mode == "transcode":
            audio_codec = self.config.get("audio_codec", "aac")
            args.extend(["-c:a", audio_codec])
            if audio_codec == "aac":
                args.extend(["-b:a", "192k"])
            elif audio_codec == "libopus":
                args.extend(["-b:a", "128k"])
        elif audio_mode == "downmix":
            args.extend(["-c:a", "aac", "-ac", "2", "-b:a", "192k"])

        return args

    def _build_subtitle_args(self) -> List[str]:
        args = []
        sub_mode = self.config.get("subtitle_mode", "copy")

        if sub_mode == "copy":
            args.extend(["-c:s", "copy"])
        elif sub_mode == "burn":
            pass
        elif sub_mode == "remove":
            args.extend(["-sn"])

        return args

    def _get_output_path(self) -> str:
        container = self.config.get("container", "mkv")
        base = os.path.splitext(self.input_path)[0]
        return f"{base}.mediaflow.{container}"
