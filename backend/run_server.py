#!/usr/bin/env python3
"""Standalone entry point for the MediaFlow backend.

Used by PyInstaller to freeze the backend into a single executable.
Accepts --port, --host, and --data-dir CLI args and sets environment
variables BEFORE importing any app modules (so pydantic-settings picks
them up).
"""

import argparse
import os
import sys


def main():
    parser = argparse.ArgumentParser(description="MediaFlow Backend Server")
    parser.add_argument("--port", type=int, default=9876, help="Port to listen on")
    parser.add_argument("--host", type=str, default="127.0.0.1", help="Host to bind to")
    parser.add_argument(
        "--data-dir",
        type=str,
        default=None,
        help="Directory for database and runtime data (default: cwd)",
    )
    args = parser.parse_args()

    # Resolve data directory
    data_dir = args.data_dir or os.getcwd()
    os.makedirs(data_dir, exist_ok=True)

    # Set env vars BEFORE any app imports so pydantic Settings reads them
    os.environ["API_PORT"] = str(args.port)
    os.environ["API_HOST"] = args.host
    os.environ["DATABASE_URL"] = f"sqlite+aiosqlite:///{os.path.join(data_dir, 'mediaflow.db')}"

    # If running from a PyInstaller bundle, add the _internal/app directory
    # to sys.path so uvicorn's string-based import can find the app package.
    if getattr(sys, "_MEIPASS", None):
        bundle_dir = sys._MEIPASS
        if bundle_dir not in sys.path:
            sys.path.insert(0, bundle_dir)

    import uvicorn

    uvicorn.run(
        "app.main:app",
        host=args.host,
        port=args.port,
        log_level="info",
    )


if __name__ == "__main__":
    main()
