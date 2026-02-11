<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple&logoColor=white" />
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white" />
  <img src="https://img.shields.io/badge/Python-3.11%2B-3776AB?style=flat-square&logo=python&logoColor=white" />
  <img src="https://img.shields.io/badge/FastAPI-0.109%2B-009688?style=flat-square&logo=fastapi&logoColor=white" />
  <img src="https://img.shields.io/badge/FFmpeg-GPL-007808?style=flat-square&logo=ffmpeg&logoColor=white" />
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" />
</p>

# MediaFlow

**Intelligent Plex media library optimizer & distributed transcoding engine for macOS.**

MediaFlow connects to your Plex servers, analyzes every file in your library, and gives you the tools to modernize codecs, reclaim storage, and orchestrate transcoding across local and remote hardware — all from a native macOS app with real-time progress.

<p align="center">
  <img src="sample_designs/media_library_dashboard/screen.png" width="90%" />
</p>

---

## Why MediaFlow?

Most Plex users accumulate terabytes of media in mixed formats over years. Old H.264 encodes sit next to modern HEVC files. 4K rips that nobody watches burn storage. Transcoding manually with FFmpeg is tedious and error-prone.

MediaFlow solves this by providing:

- **Full visibility** into your library's codec, resolution, bitrate, and audio breakdown
- **AI-driven recommendations** that identify exactly which files to transcode and why
- **Distributed transcoding** across your Mac, VPS instances, or GPU servers — simultaneously
- **Safety-first workflow** with dry-run simulation, integrity verification, and rollback support
- **Real-time monitoring** via WebSocket — watch progress bars fill across all workers at once

---

## Features

### Library Analysis & Filtering

Connect to one or more Plex servers via OAuth and sync your entire media catalog. Browse every file with full technical metadata:

- **Resolution** (4K, 1080p, 720p, SD) with HDR/SDR indicators
- **Video codec** (H.264, H.265, AV1, VP9, VC1, MPEG4)
- **Audio tracks** (Atmos, DTS-X, TrueHD, AC3, AAC, FLAC) with channel counts
- **Bitrate**, file size, duration, container format, frame rate
- **Advanced compound filters** — combine resolution + codec + bitrate + library + date range
- **Saved filter presets** for repeated queries
- **Bulk selection** — select all filtered results, entire seasons, or whole series
- **CSV/JSON export** of any filtered view

### Intelligence Engine

Five built-in recommendation analyzers scan your library and surface actionable insights:

| Analyzer | What It Finds |
|----------|---------------|
| **Codec Modernization** | H.264/MPEG4/VC1 files that benefit from H.265 conversion |
| **Quality Overkill** | 4K HDR content with minimal views — candidates for space-saving downscale |
| **Duplicate Detection** | Same content in multiple qualities or formats across libraries |
| **Quality Gap Analysis** | Files with bitrates far below your library average |
| **Storage Optimization** | Prioritized savings opportunities with estimated GB reclaimed per file |

One-click **batch queue** sends all accepted recommendations straight to the transcode pipeline.

### Transcoding Engine

<p align="center">
  <img src="sample_designs/transcode_configuration/screen.png" width="90%" />
</p>

Full control over the encoding pipeline:

- **Video**: Resolution scaling, codec selection (H.264, H.265, AV1), CRF or target bitrate
- **Audio**: Copy/passthrough, transcode to AAC/AC3, downmix, multi-track handling
- **HDR**: Preserve HDR10/Dolby Vision or tone-map to SDR
- **Hardware acceleration**: Auto-detect NVENC, QuickSync, VideoToolbox, AMD VCE
- **Two-pass encoding**, custom FFmpeg flags, encoder-specific tuning (film, animation, grain)

#### Preset System

Four built-in presets ship out of the box:

| Preset | Use Case |
|--------|----------|
| **Balanced** | Good quality-to-size ratio for general use |
| **Storage Saver** | Maximum compression for bulk libraries |
| **Mobile Optimized** | 720p / lower bitrate for mobile streaming |
| **Ultra Fidelity** | Archive-grade quality preservation |

Create, edit, export, and import your own custom presets.

#### Safety Features

- **Dry-run mode** — simulate the entire transcode without touching files
- **Integrity verification** — FFprobe validates codec, resolution, and duration match post-encode
- **Automatic backup** — optionally preserve originals before replacement
- **Rollback** — move originals to a holding area, approve or reject after verification

### Distributed Worker System

<p align="center">
  <img src="sample_designs/server_management_&_analytics/screen.png" width="90%" />
</p>

Scale transcoding across multiple machines:

- **Local macOS worker** — auto-configured, zero setup
- **Remote Linux servers** — add any Ubuntu/Debian/RHEL VPS via SSH
- **One-click provisioning** — MediaFlow SSHs into a fresh VPS and installs FFmpeg automatically (static build with libx265, libx264, libsvtav1, aac, opus)
- **GPU support** — optional NVIDIA driver installation during provisioning

#### Intelligent Job Distribution

The scheduler scores each available worker based on:

- Current CPU/GPU load (35%)
- Historical transcoding performance (30%)
- Transfer cost — network speed to/from Plex server (35%)

Jobs are automatically assigned to the best available worker, with manual override always available.

#### Network Benchmarking

Run upload/download speed tests between workers and your Plex server. Results feed into the scheduling algorithm and power per-server transcode time estimates.

#### File Transfer Modes

| Mode | When Used |
|------|-----------|
| **Local** | Worker has direct filesystem access |
| **Mapped paths** | Worker sees Plex files via network mount (NFS/SMB) |
| **SSH Pull** | Download source from NAS, transcode locally, upload result back |

Auto-detected with fallback chain. Path mappings are configurable per server.

### Real-Time Monitoring

<p align="center">
  <img src="sample_designs/active_processing_queue/screen.png" width="90%" />
</p>

Everything updates live via WebSocket:

- **Progress bars** with percentage, encoding speed (FPS), and ETA
- **Server metrics** — CPU, GPU, RAM, temperature, fan speed per worker
- **Queue stats** — pending, active, completed counts
- **Job logs** — expandable FFmpeg output for each job
- **Server health** — automatic detection of offline workers with failover

### Analytics Dashboard

Track the impact of your optimization work:

- **Total storage saved** across all completed transcodes
- **Codec distribution** before and after (pie charts)
- **Resolution breakdown** across your library
- **Job history** with per-file size reduction and timing
- **Cost tracking** for cloud VPS workers (hourly rate, total spend, cost per job)
- **Savings history** over 30/90/365 day windows

---

## Architecture

```
┌─────────────────────────────────┐
│     macOS SwiftUI Frontend      │
│   (MVVM, native dark theme)     │
│                                 │
│  Library ─ Transcode ─ Servers  │
│  Analytics ─ Recommendations    │
└──────────────┬──────────────────┘
               │ REST + WebSocket
               ▼
┌─────────────────────────────────┐
│     Python FastAPI Backend      │
│       (port 9876, async)        │
│                                 │
│  API Routes ─ Services ─ ORM   │
│  Workers ─ Scheduler ─ SSH     │
└──────┬───────────┬──────────────┘
       │           │
       ▼           ▼
┌────────────┐  ┌──────────────────┐
│   SQLite   │  │  Worker Servers  │
│  (WAL mode)│  │                  │
│            │  │  Local macOS     │
│  14 tables │  │  Remote Linux    │
│            │  │  GPU Instances   │
└────────────┘  └──────────────────┘
                       │ SSH
                       ▼
                ┌──────────────┐
                │  Plex Server │
                │  (NAS / VM)  │
                └──────────────┘
```

---

## Getting Started

### Prerequisites

- **macOS 14+** (Sonoma or later)
- **Python 3.11+** with pip
- **Swift 5.9+** (included with Xcode 15+)
- **FFmpeg** (installed locally for the local worker — `brew install ffmpeg`)
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
2. Go to **Settings** and sign in with your Plex account (OAuth)
3. Your servers and libraries sync automatically
4. Navigate to the **Library** tab to browse your media
5. Head to **Servers** to add remote workers or provision a VPS

### Adding a Remote Worker

1. Go to **Servers** → click **Add Server Node**
2. Enter the hostname, SSH port, and username for your VPS
3. Click **Add Server** — the server appears with a "pending" status
4. Click **Install FFmpeg** on the server card
5. MediaFlow SSHs in, detects the distro, installs FFmpeg, and probes capabilities
6. Once complete, the server goes "online" and is ready for transcoding jobs

> **Note**: The SSH user must be root or have passwordless sudo configured.

---

## API

The backend exposes a full REST API on `http://localhost:9876`. Interactive documentation is available at:

- **Swagger UI**: [http://localhost:9876/docs](http://localhost:9876/docs)
- **ReDoc**: [http://localhost:9876/redoc](http://localhost:9876/redoc)

Key endpoint groups:

| Prefix | Description |
|--------|-------------|
| `/api/plex` | Plex OAuth, server management, library sync |
| `/api/library` | Media queries, filtering, statistics, export |
| `/api/transcode` | Job creation, queue management, dry-run |
| `/api/presets` | Encoding preset CRUD |
| `/api/servers` | Worker servers, provisioning, benchmarks |
| `/api/analytics` | Storage savings, codec distribution, job history |
| `/api/recommendations` | Intelligent analysis and batch queueing |
| `/api/settings` | App configuration |
| `/api/logs` | Log retrieval and system diagnostics |
| `/ws` | WebSocket for real-time updates |

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | SwiftUI, AppKit (NSPanel), Combine — zero external dependencies |
| **Backend** | FastAPI, SQLAlchemy 2.0 (async), Pydantic v2, Uvicorn |
| **Database** | SQLite with WAL mode, async via aiosqlite |
| **SSH** | asyncssh for remote command execution and SFTP transfers |
| **Transcoding** | FFmpeg/FFprobe (static builds for remote workers) |
| **Real-time** | Native WebSocket with pub/sub event system |
| **HTTP Client** | httpx (async, for Plex API communication) |

---

## Project Structure

```
MediaFlow/
├── backend/
│   ├── app/
│   │   ├── main.py                 # FastAPI app with lifespan
│   │   ├── config.py               # Environment-based settings
│   │   ├── database.py             # SQLAlchemy engine + migrations
│   │   ├── api/                    # Route handlers (13 modules)
│   │   ├── models/                 # ORM models (14 tables)
│   │   ├── schemas/                # Pydantic request/response schemas
│   │   ├── services/               # Business logic layer
│   │   ├── workers/                # Background task processors
│   │   └── utils/                  # SSH, FFmpeg, FFprobe, path resolution
│   ├── requirements.txt
│   └── .env.example
├── frontend/MediaFlow/
│   ├── Package.swift               # SPM config (macOS 14+)
│   └── MediaFlow/
│       ├── App/                    # Entry point, app state
│       ├── Models/                 # Codable data models
│       ├── ViewModels/             # ObservableObject view models
│       ├── Views/                  # SwiftUI views by feature
│       ├── Services/               # API client, WebSocket client
│       ├── Networking/             # HTTP + WebSocket layers
│       ├── Theme/                  # Color system, typography
│       ├── Utilities/              # Keychain, logging, debouncing
│       └── Extensions/             # View + formatter helpers
├── sample_designs/                 # UI reference mockups
├── run.sh                          # Dev launcher
└── project_description.md          # Full specification
```

---

## Configuration

Copy the example environment file and customize as needed:

```bash
cp backend/.env.example backend/.env
```

Available settings:

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `sqlite+aiosqlite:///./mediaflow.db` | Database connection string |
| `SECRET_KEY` | `change-me-to-a-random-secret-key` | App secret for signing |
| `CORS_ORIGINS` | `["http://localhost:9876"]` | Allowed CORS origins |
| `LOG_LEVEL` | `INFO` | Logging verbosity |

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
