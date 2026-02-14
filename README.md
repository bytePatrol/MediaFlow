<p align="center">
  <img src="frontend/MediaFlow/mediaflow-logo.png" width="128" />
</p>

<h1 align="center">MediaFlow</h1>

<p align="center">
  <strong>Intelligent Plex media library optimizer & distributed transcoding engine for macOS</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/Python-3.11%2B-3776AB?style=flat-square&logo=python&logoColor=white" />
  <img src="https://img.shields.io/badge/FastAPI-0.109%2B-009688?style=flat-square&logo=fastapi&logoColor=white" />
  <img src="https://img.shields.io/badge/FFmpeg-GPL-007808?style=flat-square&logo=ffmpeg&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" />
</p>

<br />

MediaFlow connects to your Plex servers, analyzes every file in your library, and gives you the tools to modernize codecs, reclaim storage, and orchestrate transcoding across local and cloud hardware — all from a native macOS app with real-time progress.

---

## Table of Contents

- [Highlights](#highlights)
- [Features](#features)
  - [Library Analysis & Filtering](#library-analysis--filtering)
  - [Intelligence Engine](#intelligence-engine)
  - [Transcode Configuration](#transcode-configuration)
  - [Distributed Worker System](#distributed-worker-system)
  - [Cloud GPU Transcoding](#cloud-gpu-transcoding)
  - [Real-Time Processing Queue](#real-time-processing-queue)
  - [Quick Transcode](#quick-transcode)
  - [Analytics Dashboard](#analytics-dashboard)
  - [Notifications](#notifications)
  - [Automation](#automation)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Getting Started](#getting-started)
- [API Reference](#api-reference)
- [Project Structure](#project-structure)
- [Configuration](#configuration)
- [Database Schema](#database-schema)
- [License](#license)

---

## Highlights

| | |
|---|---|
| **Full library visibility** | Browse every file with codec, resolution, bitrate, HDR, and audio metadata at a glance |
| **9 intelligence analyzers** | Identify which files to transcode, how much space you'll save, and the confidence level of each recommendation |
| **Per-library analysis** | Scope recommendations, summaries, and history to individual Plex libraries |
| **Distributed transcoding** | Fan out jobs across your Mac, remote Linux servers, and on-demand cloud GPUs simultaneously |
| **Cloud GPU on demand** | Deploy Vultr A16/A40 instances with one click — auto-teardown on idle, spend cap enforcement |
| **NVENC hardware encoding** | Automatic CPU-to-GPU codec upgrade with 14x speedup (561 FPS vs 40 FPS on hevc_nvenc) |
| **Pre-upload pipeline** | While the GPU transcodes the current job, the next source file uploads in parallel |
| **6 notification channels** | Push (macOS banners), email, Discord, Slack, Telegram, and webhooks — all configurable per event |
| **Automation** | Scheduled scans, Sonarr/Radarr webhooks, folder watching, and cloud auto-deploy |
| **Real-time everything** | WebSocket-driven progress bars, encoding speed, ETA, and server metrics — no polling |

---

## Features

### Library Analysis & Filtering

Connect to one or more Plex servers via OAuth and sync your entire media catalog. Browse every file with full technical metadata and powerful compound filters.

- **Resolution** (4K, 1080p, 720p, SD) with HDR/SDR indicators
- **Video codec** (H.264, H.265, AV1, VP9, VC1, MPEG4)
- **Audio tracks** (Atmos, DTS-X, TrueHD, AC3, AAC, FLAC) with channel counts
- **Bitrate**, file size, duration, container format, frame rate
- **Advanced compound filters** — combine resolution + codec + bitrate + library + size range
- **Saved filter presets** — save, load, and delete filter configurations
- **Cross-page bulk selection** — "Select All Filtered" grabs every matching item, not just the current page
- **Custom tagging** — create color-coded tags, bulk apply/remove, filter by tag
- **Collection builder** — create Plex collections from filtered selections
- **Drag-and-drop** — drop video files onto the sidebar to jump straight to Quick Transcode
- **CSV/JSON export** of any filtered view

### Intelligence Engine

Nine built-in recommendation analyzers scan your library and surface actionable insights with estimated savings, confidence scores, and priority rankings.

| Analyzer | What It Finds |
|----------|---------------|
| **Codec Modernization** | H.264/MPEG4/VC1 files that benefit from H.265 conversion |
| **Quality Overkill** | 4K HDR content with minimal views — candidates for space-saving downscale |
| **Duplicate Detection** | Same content in multiple qualities or formats across libraries |
| **Quality Gap Analysis** | Files with bitrates far below your library average |
| **Storage Optimization** | Largest files with lowest engagement — top candidates for compression |
| **Audio Optimization** | Lossless high-channel audio (TrueHD, DTS-HD MA) eligible for downmix |
| **Container Modernize** | Legacy containers (.avi, .wmv, .mpg) for fast remux to .mkv |
| **HDR to SDR** | Low-usage HDR content for tone-mapped SDR conversion |
| **Batch Similar** | Groups of 5+ files sharing codec/resolution for batch transcode |

**Intelligent estimation pipeline:**

1. **Learned ratios** — actual compression ratios from your completed jobs (min 3 samples per codec pair, 90% confidence)
2. **Default ratios** — curated codec-pair tables (50% confidence)
3. **Bitrate analysis** — compares file bitrate to resolution reference (30% confidence)
4. **Fallback** — conservative 40% estimate (20% confidence)

**Per-library scoping** — filter recommendations, summaries, and analysis history to any individual Plex library. Analysis runs track which library was analyzed with full history and library badges in the UI.

**Priority scoring** — each recommendation is scored 0–100 based on file size (40%), codec age (25%), estimation confidence (20%), and play count (15%).

**Configurable thresholds** — 9 tunable parameters (min file size, max plays, channel threshold, batch group size, etc.) adjustable via Settings.

One-click **batch queue** sends all accepted recommendations straight to the transcode pipeline.

### Transcode Configuration

Full control over the encoding pipeline with four built-in presets and complete manual override.

- **Video** — resolution scaling, codec selection (H.264, H.265, AV1), CRF or target bitrate
- **Audio** — copy/passthrough, transcode to AAC/AC3, downmix, multi-track handling
- **HDR** — preserve HDR10/Dolby Vision or tone-map to SDR
- **Hardware acceleration** — auto-detect NVENC, QuickSync, VideoToolbox
- **Two-pass encoding**, custom FFmpeg flags, encoder-specific tuning
- **Preset import/export** — share encoding configurations as JSON

| Preset | Use Case |
|--------|----------|
| **Balanced** | Good quality-to-size ratio for general use |
| **Storage Saver** | Maximum compression for bulk libraries |
| **Mobile Optimized** | 720p / lower bitrate for mobile streaming |
| **Ultra Fidelity** | Archive-grade quality preservation |

### Distributed Worker System

Scale transcoding across multiple machines with intelligent job scheduling.

- **Local macOS worker** — auto-configured, zero setup
- **Remote Linux servers** — add any Ubuntu/Debian/RHEL VPS via SSH
- **One-click provisioning** — MediaFlow SSHs into a fresh server and installs FFmpeg + GPU drivers automatically
- **Intelligent scheduling** — composite scoring based on CPU/GPU load (35%), historical performance (30%), and transfer cost (35%)
- **Network benchmarking** — upload/download speed tests feed into the scheduling algorithm
- **Auto-failover** — detects offline workers and reassigns jobs
- **Pre-upload pipeline** — while the GPU transcodes the current job, automatically starts uploading the next job's source file
- **Parallel multi-stream SSH** — 4-stream parallel transfers for files >100MB with hardware-accelerated AES-NI cipher

#### File Transfer Modes

| Mode | When Used |
|------|-----------|
| **Local** | Worker has direct filesystem access |
| **Mapped Paths** | Worker sees Plex files via network mount (NFS/SMB) |
| **SSH Pull** | Download source from NAS, transcode locally, upload result back |

Auto-detected with fallback chain. Path mappings are configurable per server and globally.

### Cloud GPU Transcoding

Deploy GPU compute on demand from directly within the app. No manual server setup required.

- **One-click deploy** — pick a GPU plan (Vultr A16/A40), region, and idle timeout
- **Automatic provisioning** — creates instance, polls until active, SSHs in, installs FFmpeg + tests NVENC
- **NVENC auto-upgrade** — CPU codecs are automatically swapped to GPU equivalents (`libx265` -> `hevc_nvenc`)
- **NVENC failure fallback** — 2-stage: drops CUDA decode first, then falls back to full CPU encoding
- **Idle auto-teardown** — configurable timeout destroys instances when no jobs are running
- **Auto-deploy** — optionally deploy a cloud GPU automatically when jobs queue with no workers available
- **Spend caps** — monthly and per-instance caps with automatic enforcement
- **Cost tracking** — per-job and per-instance cost recorded with full analytics
- **vGPU compatibility** — auto-detects NVENC SDK version and falls back to compatible FFmpeg build (Jellyfin)
- **Orphan detection** — on startup, checks Vultr API for instances not matching any worker

| GPU Plan | VRAM | Approx. Cost |
|----------|------|-------------|
| A16 1x | 16 GB | ~$0.47/hr |
| A40 1/3 | 16 GB | ~$0.58/hr |
| A40 1/2 | 24 GB | ~$0.86/hr |

### Real-Time Processing Queue

Everything updates live via WebSocket — no polling, no refresh.

- **Progress bars** with percentage, encoding speed (FPS), and ETA per job
- **Pre-upload indicators** — shows upload progress on the next queued job while the current one transcodes
- **Server metrics** — CPU, GPU, RAM, temperature per worker
- **Queue stats** — pending, active, completed counts with aggregate FPS
- **Job logs** — expandable FFmpeg output for debugging
- **Auto-retry** — failed jobs retry with exponential backoff (1/5/15 min), configurable max retries
- **Stuck detection** — health worker flags stalled jobs after configurable timeout
- **Post-transcode validation** — ffprobe verifies output has video streams, correct file size, and matching duration
- **Drag-and-drop reordering** — prioritize jobs in the queue

### Quick Transcode

Transcode arbitrary local files — not just Plex library items — through the same GPU worker infrastructure.

- **Drag-and-drop or file picker** — supports MKV, MP4, AVI, MOV, WMV, TS, M4V, WebM
- **Instant probe** — ffprobe displays resolution, codec, bitrate, duration, audio info before you start
- **Full config** — preset selector, codec/container/resolution/CRF/audio controls, server picker
- **Non-destructive** — output saves as `{name} V2.{ext}` alongside the original

### Analytics Dashboard

Track the impact of your optimization work with a comprehensive analytics suite.

- **Library health score** — weighted 0–100 grade (codec modernity 40%, bitrate appropriateness 30%, container format 15%, audio efficiency 15%) with letter grade A–F
- **Trend KPI cards** — week-over-week comparison with directional arrows, sparkline mini-charts
- **Savings predictions** — linear extrapolation of your daily savings rate to 30/90/365-day forecasts
- **Charts** — savings over time, codec distribution donut, resolution bar chart, storage timeline with shaded savings area
- **Interactive chart tooltips** — drag across charts for point-in-time details
- **Server performance** — per-worker stats (FPS, compression ratio, failure rate, cloud badge)
- **Top opportunities** — ranked list of untranscoded files with estimated savings and one-click queue
- **Cloud costs** — hourly rate, total spend, cost per job
- **Time range filtering** — 7d / 30d / 90d / 1y across all dashboard views
- **PDF health reports** — downloadable library health report

### Notifications

Six fully configurable notification channels, each with per-event toggle control.

| Channel | Setup |
|---------|-------|
| **Push** | macOS native banner notifications — no external service needed |
| **Email** | SMTP configuration with TLS support |
| **Discord** | Webhook URL with color-coded embeds |
| **Slack** | Webhook URL with Block Kit formatting |
| **Telegram** | Bot token + chat ID with Markdown messages |
| **Webhook** | POST JSON to any URL |

**10 event types:** job completed, job failed, analysis completed, server offline, server online, cloud deploy completed, cloud teardown completed, spend cap reached, queue stalled, library sync completed.

Each channel can subscribe to any combination of events. Test buttons for every channel. Full notification history with status tracking.

### Automation

- **Scheduled library scans** — configurable interval (6h / 12h / daily / weekly) with optional post-sync analysis
- **Sonarr/Radarr webhooks** — `POST /api/webhooks/ingest/{source_id}` auto-creates transcode jobs when new media arrives
- **Folder watching** — monitor directories for new media files, auto-queue with configurable preset and delay
- **Cloud auto-deploy** — automatically spin up a cloud GPU when jobs queue with no workers available
- **Auto-analyze on sync** — intelligence analysis runs automatically after library sync

---

## Architecture

```
┌──────────────────────────────────────┐
│       macOS SwiftUI Frontend         │
│     (MVVM, native dark theme)        │
│                                      │
│  Library ─ Transcode ─ Servers       │
│  Analytics ─ Intelligence ─ Settings │
│  Menu Bar Extra ─ Command Palette    │
│  Onboarding ─ Push Notifications     │
└────────────────┬─────────────────────┘
                 │ REST + WebSocket
                 ▼
┌──────────────────────────────────────┐
│       Python FastAPI Backend         │
│        (port 9876, async)            │
│                                      │
│  17 API modules ─ 113 endpoints      │
│  14 services ─ 6 background workers  │
│  8 utility modules ─ 19 ORM models   │
└────────┬──────────────┬──────────────┘
         │              │
         ▼              ▼
┌──────────────┐  ┌────────────────────┐
│    SQLite    │  │   Worker Servers   │
│  (WAL mode)  │  │                    │
│              │  │  Local macOS       │
│  19 tables   │  │  Remote Linux      │
│              │  │  Cloud GPU (A16)   │
└──────────────┘  └────────────────────┘
                         │ SSH + SFTP
                         ▼
                  ┌──────────────┐
                  │  Plex Server │
                  │  (NAS / VM)  │
                  └──────────────┘
```

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | SwiftUI, AppKit (NSPanel), Combine — zero external dependencies |
| **Backend** | FastAPI, SQLAlchemy 2.0 (async), Pydantic v2, Uvicorn |
| **Database** | SQLite with WAL mode, async via aiosqlite |
| **SSH** | asyncssh for remote command execution, SFTP, and parallel multi-stream transfers |
| **Transcoding** | FFmpeg/FFprobe with NVENC GPU acceleration and automatic fallback |
| **Cloud** | Vultr v2 REST API (httpx async) for on-demand GPU instances |
| **Notifications** | SMTP (aiosmtplib), Discord/Slack/Telegram webhooks, macOS UNUserNotificationCenter |
| **Real-time** | Native WebSocket with pub/sub event system (25+ event types) |

---

## Getting Started

### Prerequisites

- **macOS 14+** (Sonoma or later)
- **Python 3.11+** with pip
- **Swift 5.9+** (included with Xcode 15+ command line tools)
- **FFmpeg** installed locally for the local worker — `brew install ffmpeg`
- A **Plex Media Server** with a valid account

### Installation

```bash
# Clone the repository
git clone https://github.com/bytePatrol/MediaFlow.git
cd MediaFlow

# Set up the Python backend
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cd ..

# Build the Swift frontend
cd frontend/MediaFlow
swift build
cd ../..
```

### Running

The easiest way to launch both services:

```bash
./run.sh
```

This starts the FastAPI backend on port 9876 and builds + launches the SwiftUI app.

You can also run them independently:

```bash
# Backend only
./run.sh --backend-only

# Frontend only (requires backend running)
./run.sh --frontend-only
```

Or manually:

```bash
# Terminal 1: Backend
cd backend
source venv/bin/activate
uvicorn app.main:app --port 9876 --reload

# Terminal 2: Frontend
cd frontend/MediaFlow
swift build && .build/debug/MediaFlow
```

### First Launch

1. Open MediaFlow — the app connects to the backend automatically
2. The **onboarding wizard** walks you through setup: Connect Plex (OAuth) -> Add Worker -> Ready
3. Your servers and libraries sync automatically after sign-in
4. Navigate to the **Library** tab to browse your media
5. Head to **Intelligence** to run your first analysis
6. Go to **Servers** to add remote workers or deploy a cloud GPU

---

## API Reference

The backend exposes a full REST API on `http://localhost:9876`. Interactive documentation:

- **Swagger UI**: [http://localhost:9876/docs](http://localhost:9876/docs)
- **ReDoc**: [http://localhost:9876/redoc](http://localhost:9876/redoc)

### Endpoints

| Prefix | Module | Endpoints | Description |
|--------|--------|-----------|-------------|
| `/api/health` | health.py | 1 | Health check |
| `/api/plex` | plex.py | 10 | OAuth, server management, SSH config, library sync |
| `/api/library` | library.py | 7 | Media queries, filtering, statistics, bulk ID lookup, export |
| `/api/transcode` | transcode.py | 10 | Job CRUD, queue, dry-run, probe, manual transcode |
| `/api/presets` | presets.py | 7 | Encoding preset CRUD, import/export |
| `/api/servers` | servers.py | 12 | Workers, provisioning, benchmarks, health |
| `/api/cloud` | cloud.py | 6 | GPU deploy/teardown, plans, cost tracking, settings |
| `/api/analytics` | analytics.py | 14 | Overview, trends, predictions, health score, sparklines, storage timeline, server performance |
| `/api/recommendations` | recommendations.py | 8 | Analysis (full + per-library), batch queue, summary, history, savings |
| `/api/notifications` | notifications.py | 7 | Channel CRUD, test, events registry, history |
| `/api/settings` | settings.py | 3 | App configuration key-value store |
| `/api/tags` | tags.py | 7 | Custom tag CRUD, bulk apply/remove |
| `/api/collections` | collections.py | 3 | Plex collection builder |
| `/api/filter-presets` | filter_presets.py | 4 | Saved filter preset CRUD |
| `/api/webhooks` | webhooks.py | 5 | Sonarr/Radarr source CRUD + ingest |
| `/api/watch-folders` | watch_folders.py | 5 | Watch folder CRUD + toggle |
| `/api/logs` | logs.py | 3 | Log retrieval, diagnostics, export |
| `/ws` | websocket.py | 1 | WebSocket pub/sub for real-time updates |

**Total: 113 endpoints across 18 modules**

### WebSocket Events

The `/ws` endpoint streams real-time events using a pub/sub model. Key event categories:

| Category | Events |
|----------|--------|
| **Jobs** | `job.progress`, `job.completed`, `job.failed`, `job.preupload_progress` |
| **Cloud** | `cloud.deploy_progress`, `cloud.deploy_completed`, `cloud.deploy_failed`, `cloud.teardown_completed`, `cloud.spend_cap_reached`, `cloud.auto_deploy_triggered`, `cloud.jobs_reassigned` |
| **Library** | `sync.completed`, `analysis.completed` |
| **Servers** | `server.offline`, `server.online`, `server.metrics` |
| **Notifications** | `notification.push` |

---

## Project Structure

```
MediaFlow/
├── backend/
│   ├── app/
│   │   ├── main.py                 # FastAPI app with lifespan
│   │   ├── config.py               # Environment-based settings
│   │   ├── database.py             # SQLAlchemy engine + migrations
│   │   ├── api/                    # Route handlers (18 modules)
│   │   ├── models/                 # ORM models (19 tables)
│   │   ├── schemas/                # Pydantic request/response schemas
│   │   ├── services/               # Business logic + cloud provisioning
│   │   ├── workers/                # Background processors (6 workers)
│   │   └── utils/                  # SSH, FFmpeg, FFprobe, path resolution, notifications
│   ├── requirements.txt
│   └── .env.example
├── frontend/MediaFlow/
│   ├── Package.swift               # SPM config (macOS 14+)
│   └── MediaFlow/
│       ├── App/                    # Entry point, app state
│       ├── Models/                 # Codable data models
│       ├── ViewModels/             # ObservableObject view models
│       ├── Views/                  # SwiftUI views by feature
│       │   ├── Intelligence/       # Recommendations, analysis
│       │   ├── Library/            # Media browser, filters, collections
│       │   ├── Transcode/          # Queue, job cards, manual transcode
│       │   ├── Servers/            # Worker management, cloud deploy
│       │   ├── Analytics/          # Dashboard, charts
│       │   ├── Settings/           # All settings tabs, config panels
│       │   ├── Onboarding/         # First-run wizard
│       │   ├── Logs/               # System logs
│       │   └── Components/         # Shared UI components
│       ├── Services/               # Backend API + WebSocket + Notifications
│       ├── Networking/             # HTTP + WebSocket transport layers
│       ├── Theme/                  # Color system, typography
│       ├── Utilities/              # Keychain, logging, debouncing
│       └── Extensions/             # View + formatter helpers
└── run.sh                          # Dev launcher
```

| Area | Count |
|------|-------|
| Backend Python files | 86 |
| Frontend Swift files | 73 |
| API endpoints | 113 |
| Database tables | 19 |
| Background workers | 6 |
| WebSocket event types | 25+ |

---

## Configuration

Copy the example environment file and customize:

```bash
cp backend/.env.example backend/.env
```

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `sqlite+aiosqlite:///./mediaflow.db` | Database connection string |
| `SECRET_KEY` | `change-me-to-a-random-secret-key` | App secret for signing |
| `CORS_ORIGINS` | `["http://localhost:9876"]` | Allowed CORS origins |
| `LOG_LEVEL` | `INFO` | Logging verbosity (`DEBUG`, `INFO`, `WARNING`, `ERROR`) |
| `API_PORT` | `9876` | Backend server port |
| `API_HOST` | `0.0.0.0` | Backend bind address |
| `FFMPEG_PATH` | `/usr/local/bin/ffmpeg` | Local FFmpeg binary path |
| `FFPROBE_PATH` | `/usr/local/bin/ffprobe` | Local FFprobe binary path |

Additional settings are configured in-app via **Settings**:

| Settings Tab | What It Controls |
|-------------|-----------------|
| **General** | Plex connection (OAuth), backend URL |
| **Storage** | Path mappings (NAS mount → local path) |
| **Scheduling** | Scan intervals, post-sync analysis |
| **Intelligence** | 9 analysis thresholds (min file sizes, max plays, group sizes, etc.) |
| **Cloud GPU** | Vultr API key, default plan/region, spend caps, idle timeout, auto-deploy |
| **Notifications** | Email/Discord/Slack/Telegram/Webhook/Push channel configuration |
| **API** | Sonarr/Radarr webhook sources, watch folders |

---

## Database Schema

19 tables managed via SQLAlchemy with automatic migrations:

| Table | Purpose |
|-------|---------|
| `plex_servers` | Plex server connections with SSH config |
| `plex_libraries` | Synced Plex library metadata |
| `media_items` | Full media file metadata (codec, resolution, bitrate, HDR, audio, etc.) |
| `transcode_jobs` | Job queue with status, progress, ffmpeg command, worker assignment |
| `transcode_presets` | Encoding presets (4 built-in + custom) |
| `worker_servers` | Local/remote/cloud workers with capabilities and cloud instance tracking |
| `job_logs` | Per-job completion stats (sizes, duration, FPS, codec pair, cost) |
| `recommendations` | Intelligence results with type, severity, savings, priority, confidence |
| `analysis_runs` | Analysis execution history with per-library tracking |
| `server_benchmarks` | Network speed tests per worker |
| `cloud_cost_records` | Per-job and per-instance cloud cost tracking |
| `custom_tags` | User-defined tags with colors |
| `media_tags` | Many-to-many tag assignments |
| `app_settings` | Key-value configuration store |
| `filter_presets` | Saved library filter configurations |
| `notification_configs` | Notification channel settings with event subscriptions |
| `notification_logs` | Dispatch history with status tracking |
| `webhook_sources` | Sonarr/Radarr ingest endpoints |
| `watch_folders` | Monitored directories for auto-transcode |

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
