from fastapi import APIRouter
from app.api import plex, library, transcode, presets, servers, analytics, recommendations, settings, health, notifications, logs, cloud

api_router = APIRouter()

api_router.include_router(health.router, tags=["health"])
api_router.include_router(plex.router, prefix="/plex", tags=["plex"])
api_router.include_router(library.router, prefix="/library", tags=["library"])
api_router.include_router(transcode.router, prefix="/transcode", tags=["transcode"])
api_router.include_router(presets.router, prefix="/presets", tags=["presets"])
api_router.include_router(servers.router, prefix="/servers", tags=["servers"])
api_router.include_router(analytics.router, prefix="/analytics", tags=["analytics"])
api_router.include_router(recommendations.router, prefix="/recommendations", tags=["recommendations"])
api_router.include_router(settings.router, prefix="/settings", tags=["settings"])
api_router.include_router(notifications.router, prefix="/notifications", tags=["notifications"])
api_router.include_router(logs.router, tags=["logs"])
api_router.include_router(cloud.router, prefix="/cloud", tags=["cloud"])
