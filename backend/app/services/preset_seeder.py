import logging
from sqlalchemy import select
from app.database import async_session_factory
from app.models.transcode_preset import TranscodePreset

logger = logging.getLogger(__name__)

DEFAULT_PRESETS = [
    {
        "name": "Balanced",
        "description": "Optimal quality to size ratio for home streaming.",
        "is_builtin": True,
        "video_codec": "libx265",
        "bitrate_mode": "crf",
        "crf_value": 22,
        "container": "mkv",
        "audio_mode": "copy",
        "subtitle_mode": "copy",
        "hdr_mode": "preserve",
    },
    {
        "name": "Storage Saver",
        "description": "HEVC compression targeting maximum storage reduction.",
        "is_builtin": True,
        "video_codec": "libx265",
        "bitrate_mode": "crf",
        "crf_value": 26,
        "container": "mkv",
        "audio_mode": "transcode",
        "audio_codec": "aac",
        "subtitle_mode": "copy",
        "hdr_mode": "tonemap",
    },
    {
        "name": "Mobile Optimized",
        "description": "H.264 at 1080p for broad device compatibility.",
        "is_builtin": True,
        "video_codec": "libx264",
        "target_resolution": "1080p",
        "bitrate_mode": "crf",
        "crf_value": 23,
        "container": "mp4",
        "audio_mode": "transcode",
        "audio_codec": "aac",
        "subtitle_mode": "burn",
        "hdr_mode": "tonemap",
    },
    {
        "name": "Ultra Fidelity",
        "description": "Near-lossless AV1 encoding for archival purposes.",
        "is_builtin": True,
        "video_codec": "libsvtav1",
        "bitrate_mode": "crf",
        "crf_value": 18,
        "container": "mkv",
        "audio_mode": "copy",
        "subtitle_mode": "copy",
        "hdr_mode": "preserve",
        "two_pass": True,
    },
]


async def seed_default_presets():
    async with async_session_factory() as session:
        for preset_data in DEFAULT_PRESETS:
            result = await session.execute(
                select(TranscodePreset).where(
                    TranscodePreset.name == preset_data["name"],
                    TranscodePreset.is_builtin == True,
                )
            )
            existing = result.scalar_one_or_none()
            if not existing:
                preset = TranscodePreset(**preset_data)
                session.add(preset)
                logger.info(f"Seeded preset: {preset_data['name']}")
        await session.commit()
