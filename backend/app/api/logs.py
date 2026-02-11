import logging
import os
import platform
import sys
from collections import deque
from datetime import datetime

from fastapi import APIRouter

router = APIRouter()


class InMemoryLogHandler(logging.Handler):
    """Captures log records into a bounded deque for retrieval via API."""

    def __init__(self, max_lines: int = 2000):
        super().__init__()
        self.records: deque = deque(maxlen=max_lines)

    def emit(self, record):
        try:
            entry = {
                "timestamp": datetime.fromtimestamp(record.created).isoformat(),
                "level": record.levelname,
                "logger": record.name,
                "message": record.getMessage(),
            }
            self.records.append(entry)
        except Exception:
            pass


# Singleton handler — attached to root logger in main.py lifespan
log_handler = InMemoryLogHandler()
log_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)-8s %(name)s: %(message)s"))


def install_log_handler():
    """Call once at startup to attach the in-memory handler to the root logger."""
    root = logging.getLogger()
    root.addHandler(log_handler)


@router.get("/logs")
async def get_logs(
    level: str = None,
    logger_name: str = None,
    limit: int = 500,
    offset: int = 0,
):
    """Return recent log entries with optional filtering."""
    entries = list(log_handler.records)

    if level:
        level_upper = level.upper()
        entries = [e for e in entries if e["level"] == level_upper]

    if logger_name:
        entries = [e for e in entries if logger_name in e["logger"]]

    total = len(entries)
    # Most recent first
    entries = list(reversed(entries))
    entries = entries[offset:offset + limit]

    return {"items": entries, "total": total}


@router.get("/logs/diagnostics")
async def get_diagnostics():
    """Return system and app diagnostic information."""
    import app

    # Disk usage for temp dir
    working_dir = "/tmp/mediaflow"
    cache_size = 0
    cache_files = 0
    if os.path.exists(working_dir):
        for entry in os.listdir(working_dir):
            path = os.path.join(working_dir, entry)
            if os.path.isfile(path):
                cache_size += os.path.getsize(path)
                cache_files += 1

    # DB size
    db_path = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(__file__))), "mediaflow.db")
    db_size = os.path.getsize(db_path) if os.path.exists(db_path) else 0

    return {
        "system": {
            "platform": platform.platform(),
            "python_version": sys.version,
            "architecture": platform.machine(),
            "hostname": platform.node(),
        },
        "app": {
            "version": "1.0.0",
            "pid": os.getpid(),
            "uptime_seconds": None,  # Could track via lifespan
            "db_size_bytes": db_size,
            "cache_dir": working_dir,
            "cache_size_bytes": cache_size,
            "cache_files": cache_files,
            "log_buffer_size": len(log_handler.records),
            "log_buffer_capacity": log_handler.records.maxlen,
        },
    }


@router.get("/logs/export")
async def export_logs():
    """Return all logs as plain text for file export."""
    from fastapi.responses import PlainTextResponse

    lines = []
    for entry in log_handler.records:
        lines.append(f"{entry['timestamp']} {entry['level']:<8} {entry['logger']}: {entry['message']}")

    return PlainTextResponse(
        content="\n".join(lines),
        media_type="text/plain",
        headers={"Content-Disposition": f"attachment; filename=mediaflow-logs-{datetime.now().strftime('%Y%m%d-%H%M%S')}.txt"},
    )
