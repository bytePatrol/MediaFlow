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

    # Import the FastAPI app object directly after env vars are set.
    # Passing the object (not a string) to uvicorn.run() lets PyInstaller
    # trace all imports statically so every dependency gets frozen correctly.
    from app.main import app as fastapi_app
    import uvicorn

    uvicorn.run(
        fastapi_app,
        host=args.host,
        port=args.port,
        log_level="info",
    )


if __name__ == "__main__":
    main()
