import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import init_database
from app.api.router import api_router
from app.api.websocket import websocket_router
from app.services.preset_seeder import seed_default_presets
from app.workers.scheduler import start_scheduler, stop_scheduler
from app.api.logs import install_log_handler

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    logging.basicConfig(level=getattr(logging, settings.LOG_LEVEL))
    install_log_handler()
    logger.info("Starting MediaFlow backend...")
    await init_database()
    await seed_default_presets()
    await start_scheduler()
    logger.info(f"MediaFlow backend ready on port {settings.API_PORT}")
    yield
    await stop_scheduler()
    logger.info("Shutting down MediaFlow backend...")


app = FastAPI(
    title="MediaFlow API",
    description="Plex Media Library Optimizer & Distributed Transcoder",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix="/api")
app.include_router(websocket_router)
