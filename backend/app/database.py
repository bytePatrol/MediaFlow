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
        server_benchmark,
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
    ]
    for table, column, col_type in migrations:
        try:
            await conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {col_type}"))
        except Exception:
            pass  # Column already exists
