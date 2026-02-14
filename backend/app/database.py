from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy import event, text

from app.config import settings


class Base(DeclarativeBase):
    pass


engine = create_async_engine(
    settings.DATABASE_URL,
    echo=settings.LOG_LEVEL == "DEBUG",
    connect_args={"check_same_thread": False},
)

async_session_factory = async_sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)


async def get_session() -> AsyncSession:
    async with async_session_factory() as session:
        yield session


async def init_database():
    from app.models import (  # noqa: F401
        plex_server, plex_library, media_item, transcode_preset,
        transcode_job, worker_server, job_log, recommendation,
        custom_tag, notification_config, app_settings, filter_preset,
        server_benchmark, cloud_cost, notification_log,
    )
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await conn.execute(text("PRAGMA journal_mode=WAL"))
        await conn.execute(text("PRAGMA synchronous=NORMAL"))
        await conn.execute(text("PRAGMA foreign_keys=ON"))
        await _run_migrations(conn)


async def _run_migrations(conn):
    """Add columns that create_all won't add to existing tables."""
    migrations = [
        ("worker_servers", "path_mappings", "TEXT"),
        ("transcode_jobs", "transfer_mode", "VARCHAR(20)"),
        ("transcode_jobs", "worker_input_path", "VARCHAR(2000)"),
        ("transcode_jobs", "worker_output_path", "VARCHAR(2000)"),
        ("plex_servers", "ssh_hostname", "VARCHAR(255)"),
        ("plex_servers", "ssh_port", "INTEGER DEFAULT 22"),
        ("plex_servers", "ssh_username", "VARCHAR(100)"),
        ("plex_servers", "ssh_key_path", "VARCHAR(500)"),
        ("plex_servers", "ssh_password", "VARCHAR(500)"),
        ("worker_servers", "performance_score", "FLOAT"),
        ("worker_servers", "last_benchmark_at", "DATETIME"),
        ("worker_servers", "consecutive_failures", "INTEGER DEFAULT 0"),
        ("worker_servers", "provision_log", "TEXT"),
        ("plex_servers", "benchmark_path", "VARCHAR(500)"),
        # Cloud GPU columns
        ("worker_servers", "cloud_provider", "VARCHAR(20)"),
        ("worker_servers", "cloud_instance_id", "VARCHAR(100)"),
        ("worker_servers", "cloud_plan", "VARCHAR(50)"),
        ("worker_servers", "cloud_region", "VARCHAR(20)"),
        ("worker_servers", "cloud_created_at", "DATETIME"),
        ("worker_servers", "cloud_auto_teardown", "BOOLEAN DEFAULT 1"),
        ("worker_servers", "cloud_idle_minutes", "INTEGER DEFAULT 30"),
        ("worker_servers", "cloud_status", "VARCHAR(20)"),
        ("transcode_jobs", "status_detail", "VARCHAR(500)"),
        # Intelligence system improvements
        ("recommendations", "priority_score", "FLOAT"),
        ("recommendations", "confidence", "FLOAT"),
        ("recommendations", "analysis_run_id", "INTEGER REFERENCES analysis_runs(id)"),
        ("notification_configs", "last_triggered_at", "DATETIME"),
        ("notification_configs", "trigger_count", "INTEGER DEFAULT 0"),
        # Pre-upload pipeline
        ("transcode_jobs", "source_prestaged", "BOOLEAN DEFAULT 0"),
    ]
    for table, column, col_type in migrations:
        try:
            await conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {col_type}"))
        except Exception:
            pass  # Column already exists
