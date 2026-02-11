#!/usr/bin/env bash
#
# MediaFlow - Development Run Script
# Starts the backend API server and/or builds & launches the macOS frontend.
#
# Usage:
#   ./run.sh                  Start both backend and frontend
#   ./run.sh --backend-only   Start only the backend API server
#   ./run.sh --frontend-only  Build and launch only the frontend app
#

set -euo pipefail

# ──────────────────────────────────────────────
# Resolve project root (directory containing this script)
# ──────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

BACKEND_DIR="$PROJECT_ROOT/backend"
FRONTEND_DIR="$PROJECT_ROOT/frontend/MediaFlow"

# ──────────────────────────────────────────────
# Configuration
# ──────────────────────────────────────────────
BACKEND_HOST="${MEDIAFLOW_HOST:-0.0.0.0}"
BACKEND_PORT="${MEDIAFLOW_PORT:-9876}"

# ──────────────────────────────────────────────
# Colors for output
# ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ──────────────────────────────────────────────
# PID tracking for cleanup
# ──────────────────────────────────────────────
BACKEND_PID=""
FRONTEND_PID=""

cleanup() {
    echo ""
    echo -e "${YELLOW}[MediaFlow]${NC} Shutting down..."

    if [[ -n "$BACKEND_PID" ]] && kill -0 "$BACKEND_PID" 2>/dev/null; then
        echo -e "${YELLOW}[MediaFlow]${NC} Stopping backend (PID $BACKEND_PID)..."
        kill "$BACKEND_PID" 2>/dev/null || true
        wait "$BACKEND_PID" 2>/dev/null || true
    fi

    if [[ -n "$FRONTEND_PID" ]] && kill -0 "$FRONTEND_PID" 2>/dev/null; then
        echo -e "${YELLOW}[MediaFlow]${NC} Stopping frontend (PID $FRONTEND_PID)..."
        kill "$FRONTEND_PID" 2>/dev/null || true
        wait "$FRONTEND_PID" 2>/dev/null || true
    fi

    echo -e "${GREEN}[MediaFlow]${NC} All processes stopped."
    exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# ──────────────────────────────────────────────
# Start backend
# ──────────────────────────────────────────────
start_backend() {
    echo -e "${BLUE}[Backend]${NC} Starting FastAPI server..."

    if [[ ! -d "$BACKEND_DIR" ]]; then
        echo -e "${RED}[Backend]${NC} Error: Backend directory not found at $BACKEND_DIR"
        exit 1
    fi

    if [[ ! -d "$BACKEND_DIR/venv" ]]; then
        echo -e "${RED}[Backend]${NC} Error: Virtual environment not found at $BACKEND_DIR/venv"
        echo -e "${RED}[Backend]${NC} Run: cd $BACKEND_DIR && python3 -m venv venv && source venv/bin/activate && pip install -r requirements.txt"
        exit 1
    fi

    (
        cd "$BACKEND_DIR"
        source venv/bin/activate
        echo -e "${CYAN}[Backend]${NC} Listening on http://$BACKEND_HOST:$BACKEND_PORT"
        exec uvicorn app.main:app \
            --host "$BACKEND_HOST" \
            --port "$BACKEND_PORT" \
            --reload \
            --log-level info
    ) &
    BACKEND_PID=$!
    echo -e "${GREEN}[Backend]${NC} Started with PID $BACKEND_PID"
}

# ──────────────────────────────────────────────
# Build and launch frontend
# ──────────────────────────────────────────────
start_frontend() {
    echo -e "${BLUE}[Frontend]${NC} Building SwiftUI application..."

    if [[ ! -d "$FRONTEND_DIR" ]]; then
        echo -e "${RED}[Frontend]${NC} Error: Frontend directory not found at $FRONTEND_DIR"
        exit 1
    fi

    if [[ ! -f "$FRONTEND_DIR/Package.swift" ]]; then
        echo -e "${RED}[Frontend]${NC} Error: Package.swift not found at $FRONTEND_DIR"
        exit 1
    fi

    (
        cd "$FRONTEND_DIR"
        echo -e "${CYAN}[Frontend]${NC} Running swift build..."
        swift build 2>&1 | while IFS= read -r line; do
            echo -e "${CYAN}[Frontend]${NC} $line"
        done

        if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
            echo -e "${RED}[Frontend]${NC} Build failed."
            exit 1
        fi

        echo -e "${GREEN}[Frontend]${NC} Build succeeded. Launching MediaFlow..."

        # Find the built executable
        EXECUTABLE="$(swift build --show-bin-path)/MediaFlow"
        if [[ -f "$EXECUTABLE" ]]; then
            exec "$EXECUTABLE"
        else
            echo -e "${RED}[Frontend]${NC} Error: Built executable not found at $EXECUTABLE"
            exit 1
        fi
    ) &
    FRONTEND_PID=$!
    echo -e "${GREEN}[Frontend]${NC} Build started with PID $FRONTEND_PID"
}

# ──────────────────────────────────────────────
# Parse arguments
# ──────────────────────────────────────────────
RUN_BACKEND=true
RUN_FRONTEND=true

case "${1:-}" in
    --backend-only)
        RUN_FRONTEND=false
        echo -e "${GREEN}[MediaFlow]${NC} Running backend only."
        ;;
    --frontend-only)
        RUN_BACKEND=false
        echo -e "${GREEN}[MediaFlow]${NC} Running frontend only."
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo ""
        echo "Options:"
        echo "  --backend-only   Start only the backend API server"
        echo "  --frontend-only  Build and launch only the frontend app"
        echo "  --help, -h       Show this help message"
        echo ""
        echo "Environment variables:"
        echo "  MEDIAFLOW_HOST   Backend host (default: 0.0.0.0)"
        echo "  MEDIAFLOW_PORT   Backend port (default: 9876)"
        exit 0
        ;;
    "")
        echo -e "${GREEN}[MediaFlow]${NC} Starting backend and frontend..."
        ;;
    *)
        echo -e "${RED}[MediaFlow]${NC} Unknown option: $1"
        echo "Run '$0 --help' for usage information."
        exit 1
        ;;
esac

# ──────────────────────────────────────────────
# Launch
# ──────────────────────────────────────────────
if [[ "$RUN_BACKEND" == true ]]; then
    start_backend
fi

if [[ "$RUN_FRONTEND" == true ]]; then
    # If running both, give the backend a moment to start
    if [[ "$RUN_BACKEND" == true ]]; then
        echo -e "${YELLOW}[MediaFlow]${NC} Waiting 2 seconds for backend to initialize..."
        sleep 2
    fi
    start_frontend
fi

# ──────────────────────────────────────────────
# Wait for processes
# ──────────────────────────────────────────────
echo -e "${GREEN}[MediaFlow]${NC} Press Ctrl+C to stop all services."

# Wait for whichever processes are running
if [[ "$RUN_BACKEND" == true ]] && [[ -n "$BACKEND_PID" ]]; then
    wait "$BACKEND_PID" 2>/dev/null || true
fi

if [[ "$RUN_FRONTEND" == true ]] && [[ -n "$FRONTEND_PID" ]]; then
    wait "$FRONTEND_PID" 2>/dev/null || true
fi
