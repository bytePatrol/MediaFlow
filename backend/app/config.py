from pydantic_settings import BaseSettings
from typing import List
import json
import shutil


def _find_binary(name: str, fallback: str) -> str:
    return shutil.which(name) or fallback


class Settings(BaseSettings):
    DATABASE_URL: str = "sqlite+aiosqlite:///./mediaflow.db"
    FFMPEG_PATH: str = _find_binary("ffmpeg", "/usr/local/bin/ffmpeg")
    FFPROBE_PATH: str = _find_binary("ffprobe", "/usr/local/bin/ffprobe")
    LOG_LEVEL: str = "INFO"
    API_PORT: int = 9876
    API_HOST: str = "0.0.0.0"
    SECRET_KEY: str = "change-me-to-a-random-secret-key"
    CORS_ORIGINS: str = '["http://localhost:9876"]'
    PLEX_CLIENT_IDENTIFIER: str = "mediaflow-app-001"
    PLEX_PRODUCT_NAME: str = "MediaFlow"

    @property
    def cors_origins_list(self) -> List[str]:
        return json.loads(self.CORS_ORIGINS)

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
