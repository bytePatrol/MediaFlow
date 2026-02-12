# MediaFlow — Project Progress

**Last Updated**: 2026-02-12
**GitHub**: https://github.com/bytePatrol/MediaFlow
**License**: MIT

---

## How to Resume

```bash
# Start everything
cd "/Users/ryan/Library/CloudStorage/Dropbox/Custom Apps/Projects/MediaFlow"
./run.sh

# Backend only
./run.sh --backend-only

# Frontend only (requires backend running)
./run.sh --frontend-only
```

Backend runs on **port 9876**. Swagger docs at http://localhost:9876/docs.

### Setup on New Machine

```bash
# Backend setup
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Frontend — requires Xcode Command Line Tools
xcode-select --install  # If not already installed

# Run everything
cd ..
chmod +x run.sh
./run.sh
```

---

## Current File Counts

| Area | Count |
|------|-------|
| Backend Python files | ~70 |
| Frontend Swift files | ~58 |
| API endpoints | 63 (57 original + 6 cloud) |
| Database models (tables) | 15 |
| Backend services | 13 |
| Background workers | 5 (transcode, health, cloud_monitor, sync, scheduler) |
| Frontend views | 27 |
| Frontend view models | 8 |
| Built-in transcode presets | 4 (Balanced, Storage Saver, Mobile Optimized, Ultra Fidelity) |

---

## Phase Completion Status

### Phase 1: Foundation — COMPLETE
- [x] FastAPI backend with async SQLAlchemy + SQLite WAL
- [x] SwiftUI macOS app shell with sidebar navigation
- [x] Database schema (15 models)
- [x] REST API structure with router aggregation
- [x] WebSocket real-time event system (pub/sub)
- [x] Plex OAuth authentication flow
- [x] Plex server discovery and auto-sync

### Phase 2: Core Features — COMPLETE
- [x] Library browser with sortable columns and metadata display
- [x] Advanced filtering (resolution, codec, audio, bitrate, HDR, size, date)
- [x] Saved filter presets
- [x] Bulk selection (all filtered, by series/season)
- [x] CSV/JSON export
- [x] Transcode job creation (single, multi-file, batch)
- [x] Encoding configuration (video, audio, subtitles, HDR, HW accel)
- [x] Processing queue with drag-and-drop reordering
- [x] Dry-run simulation mode
- [x] Preset system (built-in + custom CRUD)

### Phase 3: Intelligence — COMPLETE
- [x] Codec Modernization analyzer
- [x] Quality Overkill detection
- [x] Duplicate Detection
- [x] Quality Gap Analysis
- [x] Storage Optimization recommendations
- [x] Recommendation summary dashboard
- [x] One-click batch queue from recommendations
- [x] Dismiss/action tracking

### Phase 4: Distributed System — COMPLETE
- [x] Worker server CRUD (local + remote via SSH)
- [x] SSH connection testing
- [x] Server capability probing (CPU, GPU, RAM, ffmpeg)
- [x] Intelligent job scheduling (composite scoring: transfer 35%, perf 30%, load 35%)
- [x] Network benchmarking (upload/download speed to Plex server)
- [x] Performance scoring and transcode time estimation
- [x] Server health monitoring with heartbeat
- [x] Auto-disable after consecutive failures
- [x] VPS auto-provisioning (one-click ffmpeg install via SSH)
- [x] SSH Pull transfer mode (download → transcode local → upload back)
- [x] Path mapping support (NAS mount → local path)
- [x] Real-time server metrics via WebSocket
- [x] **Cloud GPU on-demand transcoding (Vultr A16/A40)** ← NEW

### Phase 5: Advanced Features — 70% COMPLETE
- [x] Analytics dashboard (overview, storage savings, codec/resolution charts)
- [x] Job history with per-file stats
- [x] Cost tracking for cloud VPS workers
- [x] Savings history (30/90/365 day windows)
- [x] Server comparison view
- [x] Logs view with filtering and export
- [x] System diagnostics endpoint
- [x] **Cloud cost analytics card with spend tracking** ← NEW
- [ ] **Custom tagging system** (backend model exists, frontend UI pending)
- [ ] **Batch metadata editing** (backend ready, frontend pending)
- [ ] **Collection builder** (backend ready, frontend pending)

### Phase 6: Polish & Integration — 50% COMPLETE
- [x] WebSocket notifications for all events
- [x] Active jobs dock (floating job progress)
- [x] Quality badges with color coding
- [x] Loading skeletons for async states
- [x] Glassmorphic dark theme (#256af4 primary)
- [x] NSPanel modals for proper keyboard focus (macOS SPM workaround)
- [ ] **Email notifications** (backend service exists, UI config pending)
- [ ] **Push notifications** (not started)
- [ ] **Webhook notifications** (not started)

### Phase 7: Documentation & Release — COMPLETE (for public release)
- [x] README.md with full feature docs, build instructions, API reference
- [x] Architecture diagram
- [x] Sample design screenshots in README
- [x] MIT License
- [x] .env.example with placeholder values
- [x] GitHub repo with description and 14 topic tags

---

## Architecture Overview

```
Frontend (SwiftUI macOS 14+)
  └── MVVM pattern
  └── APIClient (REST) + WebSocketClient (real-time)
  └── BackendService (typed API wrapper)
  └── 8 ViewModels → 27 Views

Backend (Python FastAPI, port 9876)
  └── 15 API route files → 63 endpoints
  └── 13 services (business logic)
  └── 5 background workers (transcode, health, cloud_monitor, sync, scheduler)
  └── 7 utility modules (SSH, FFmpeg, FFprobe, paths, security)
  └── SQLite with WAL mode, async via aiosqlite
  └── 15 ORM models
```

---

## Backend API Route Map

| Route Prefix | File | Endpoints | Purpose |
|-------------|------|-----------|---------|
| `/api/health` | health.py | 1 | Health check |
| `/api/plex` | plex.py | 9 | Plex OAuth, server mgmt, sync |
| `/api/library` | library.py | 5 | Media queries, stats, export |
| `/api/transcode` | transcode.py | 8 | Job CRUD, queue, dry-run |
| `/api/presets` | presets.py | 5 | Encoding preset CRUD |
| `/api/servers` | servers.py | 12 | Workers, provision, benchmark |
| `/api/analytics` | analytics.py | 6 | Stats, charts, savings |
| `/api/recommendations` | recommendations.py | 5 | Analysis, batch queue |
| `/api/settings` | settings.py | 3 | App configuration |
| `/api/notifications` | notifications.py | 3 | Notification config |
| `/api/cloud` | cloud.py | 6 | **Cloud GPU deploy/teardown, plans, costs, settings** |
| `/api/logs` | logs.py | 3 | Logs, diagnostics, export |
| `/ws` | websocket.py | 1 | WebSocket pub/sub |

---

## Frontend View Map

| Feature Area | Views | ViewModel |
|-------------|-------|-----------|
| Navigation | ContentView, SidebarView | — |
| Library | LibraryDashboardView, MediaTableView, MediaRowView, FilterSidebarView, FilterPillBarView | LibraryViewModel |
| Transcode | ProcessingQueueView, TranscodeConfigModal, TranscodeJobCardView, ActiveJobsDockView | TranscodeViewModel, TranscodeConfigViewModel |
| Servers | ServerManagementView, ServerCardView, AddServerSheet, **CloudDeployPanel**, ServerComparisonView | ServerManagementViewModel |
| Analytics | AnalyticsDashboardView, StatisticsCardView | AnalyticsViewModel |
| Intelligence | RecommendationsView, RecommendationCardView | RecommendationViewModel |
| Settings | SettingsView (**incl. Cloud GPU tab, CloudAPIKeyPanel**) | PlexAuthViewModel |
| Logs | LogsView | LogsViewModel |
| Components | EmptyStateView, GlassPanel, LoadingSkeleton, QualityBadge, StatusIndicator | — |

---

## Database Models (15 tables)

| Model | Table | Key Fields |
|-------|-------|------------|
| PlexServer | plex_servers | name, url, token, machine_id, SSH fields |
| PlexLibrary | plex_libraries | title, type, total_items, plex_server_id |
| MediaItem | media_items | title, codec, resolution, bitrate, file_size, hdr, duration, path |
| TranscodeJob | transcode_jobs | status, progress, ffmpeg_command, worker_server_id, transfer_mode |
| TranscodePreset | transcode_presets | name, codec, quality, hw_accel, is_builtin |
| WorkerServer | worker_servers | hostname, SSH creds, capabilities, status, **cloud_* fields** |
| JobLog | job_logs | size_before, size_after, duration, avg_fps, cost |
| Recommendation | recommendations | type, severity, estimated_savings, dismissed, actioned |
| ServerBenchmark | server_benchmarks | upload_mbps, download_mbps, latency_ms |
| **CloudCostRecord** | **cloud_cost_records** | **worker_server_id, job_id, hourly_rate, cost_usd, record_type** |
| CustomTag | custom_tags | name, color, category |
| MediaTag | media_tags | media_item_id, custom_tag_id (join table) |
| AppSetting | app_settings | key, value (KV store) |
| FilterPreset | filter_presets | name, filters (JSON) |
| NotificationConfig | notification_configs | channel, events, enabled |

---

## Cloud GPU Feature (Vultr) — Implemented 2026-02-11

### End-to-End Flow
1. User enters Vultr API key in Settings → Cloud GPU
2. User clicks "Deploy Cloud GPU" in Server Management
3. Picks GPU plan (A16/A40), region, idle timeout → Deploy
4. Backend: Vultr API creates instance → polls until active → SSH bootstrap (ffmpeg + NVIDIA drivers) → registers as WorkerServer
5. Health worker picks it up, collects GPU metrics
6. Worker assignment scoring includes it for new jobs
7. Jobs use existing ssh_transfer pipeline (upload → remote ffmpeg with streaming progress → download)
8. CloudMonitorWorker watches for idle → auto-teardown after configurable timeout
9. Cost tracked per-job and per-instance in CloudCostRecord

### Files Created
- `backend/app/models/cloud_cost.py` — CloudCostRecord model
- `backend/app/services/vultr_client.py` — Vultr v2 REST API client (httpx async)
- `backend/app/services/cloud_provisioning_service.py` — Deploy/teardown orchestration
- `backend/app/schemas/cloud.py` — Cloud request/response schemas
- `backend/app/api/cloud.py` — 6 cloud API routes
- `backend/app/workers/cloud_monitor.py` — Idle/spend monitoring (60s interval)
- `frontend/.../Views/Servers/CloudDeployPanel.swift` — NSPanel deploy form

### Files Modified
- `worker_server.py` model — 8 `cloud_*` columns
- `database.py` — migrations + cloud_cost import
- `scheduler.py` — starts CloudMonitorWorker
- `transcode_worker.py` — transfer progress callbacks, streaming SSH ffmpeg, per-job cost recording
- `ssh.py` — `run_command_streaming()` for real-time ffmpeg over SSH
- `server.py` schema — cloud fields in WorkerServerResponse
- `router.py` — registered /api/cloud
- `WorkerServer.swift` — cloud fields + 7 new model structs
- `BackendService.swift` — 6 cloud API methods
- `ServerManagementView.swift` — Deploy Cloud GPU button
- `ServerCardView.swift` — cloud icon/badge, cost ticker, teardown button, deploy progress
- `ServerManagementViewModel.swift` — cloud state + 5 WebSocket subscriptions
- `SettingsView.swift` — Cloud GPU settings tab with API key panel + spend caps
- `AnalyticsDashboardView.swift` — Cloud costs card
- `AnalyticsViewModel.swift` — cloudCosts property

### WebSocket Events
- `cloud.deploy_progress` — {server_id, step, progress, message}
- `cloud.deploy_completed` — {server_id, instance_ip, gpu_model}
- `cloud.deploy_failed` — {server_id, error}
- `cloud.teardown_completed` — {server_id, total_cost}
- `cloud.spend_cap_reached` — {server_id, cap_type, current_cost, cap}

### AppSettings Keys (stored in app_settings table)
- `vultr_api_key` — Vultr API key string
- `vultr_ssh_key_id` — Vultr SSH key ID (auto-managed)
- `cloud_default_plan` — default "vcg-a16-6c-64g-16vram"
- `cloud_default_region` — default "ewr"
- `cloud_monthly_spend_cap` — default 100.0
- `cloud_instance_spend_cap` — default 50.0
- `cloud_default_idle_minutes` — default 30
- `path_mappings` — JSON array of `{source_prefix, target_prefix}` for NAS path resolution

### Safety Guarantees
1. Provisioning failure → teardown instance immediately, mark WorkerServer as failed
2. App shutdown → CloudMonitorWorker warns about active instances
3. Spend cap → auto-teardown + WebSocket notification
4. Idle timeout → auto-teardown after configurable minutes of no active jobs
5. Orphan detection → on startup, checks Vultr API for "mediaflow-*" instances not matching any WorkerServer

### Bugs Fixed (2026-02-11 session 2)
1. **Vultr API 400 "Invalid plan chosen"** — All hardcoded GPU plan IDs were wrong (e.g., `vcg-a16-8c-64g-16vram` doesn't exist). Fixed: `list_gpu_plans()` now queries `GET /v2/plans?type=vcg` live from Vultr API. Plans are filtered to 3 curated options in `ALLOWED_GPU_PLANS`.
2. **Vultr API 400 on instance creation** — Hardcoded Ubuntu OS ID was stale. Fixed: `_get_ubuntu_os_id()` dynamically queries `/v2/os`.
3. **SSH unreachable after instance active** — Vultr cloud-init runs `apt upgrade` before enabling SSH (takes 3-5 min). Fixed: added Vultr startup script (`_ensure_startup_script()`) that opens port 22 after cloud-init, and increased SSH wait timeout to 10 minutes.
4. **SSH key mismatch** — `_ensure_ssh_key()` could reuse a stale Vultr key that didn't match the local private key. Fixed: now compares public key content and re-uploads on mismatch.
5. **Upload fails on SMB/NFS mounts** — `sftp.put()` uses `sendfile()` which fails with `[Errno 45]` on network mounts. Fixed: `_chunked_upload()` fallback reads file in 1MB chunks.
6. **Wrong ffmpeg path on remote** — FFmpeg command used local Mac path (`/opt/homebrew/bin/ffmpeg`). Fixed: replaced with bare `ffmpeg` for remote execution.
7. **NAS path not resolved** — Plex reports NAS paths (`/share/ZFS18_DATA/Media/...`) that don't exist locally. Fixed: added app-level `path_mappings` setting in addition to per-worker mappings.
8. **Vultr startup script not base64** — Vultr API requires base64-encoded script content. Fixed.
9. **Vultr error messages swallowed** — `raise_for_status()` didn't include Vultr's error body. Fixed: `_check_response()` includes full error JSON.

### Bugs Fixed & Improvements (2026-02-11 session 3)
1. **Vultr plan info now fetched live** — Replaced entire hardcoded `GPU_PLAN_INFO` dict with `ALLOWED_GPU_PLANS` (3 curated plan IDs). `list_gpu_plans()` queries `GET /v2/plans?type=vcg` from Vultr API for real pricing/specs. Hourly cost derived as `monthly_cost / 730`.
2. **Dynamic OS ID lookup** — `_get_ubuntu_os_id()` queries `/v2/os` for Ubuntu 24.04 or 22.04. No more hardcoded OS IDs.
3. **Vultr startup script for SSH** — `_ensure_startup_script()` creates a base64-encoded "mediaflow-init" boot script that opens port 22 after cloud-init finishes.
4. **SSH key mismatch detection** — `_ensure_ssh_key()` compares local public key with Vultr's stored key, deletes and re-uploads on mismatch.
5. **SSH wait timeout → 10 minutes** — Vultr cloud-init runs `apt upgrade` before SSH is available. Increased from 180s to 600s with detailed progress logging.
6. **Chunked SFTP upload for SMB mounts** — `sftp.put()` fails with `[Errno 45]` on SMB/NFS mounts. New `_chunked_upload()` fallback reads in 1MB chunks.
7. **App-level path mappings in transcode worker** — Worker now checks `app_settings` path_mappings in addition to per-worker mappings.
8. **Remote ffmpeg path fix** — Strips local Mac path (`/opt/homebrew/bin/ffmpeg`) and uses bare `ffmpeg` for remote execution.
9. **Spend cap controls → Sliders** — SettingsView replaced TextFields with Sliders for monthly and per-instance spend caps (avoids macOS SPM keyboard focus issues).
10. **Vultr error messages** — All `raise_for_status()` replaced with `_check_response()` that includes Vultr's actual error body.
11. **Default plan ID corrected** — Updated all references from `vcg-a16-8c-64g-16vram` (doesn't exist) to `vcg-a16-6c-64g-16vram`.
12. **Plans endpoint requires API key** — `list_gpu_plans()` now returns HTTP 400 if no Vultr API key configured instead of returning stale static data.

### NVENC GPU Encoding — Fully Working (2026-02-11 session 4)

**Result**: Cloud GPU transcoding now works end-to-end. Achieved **561 FPS with hevc_nvenc** vs 40 FPS with libx265 (14x speedup).

#### What Was Built
1. **Auto-upgrade CPU → GPU codec** (`transcode_service.py`): When a job is assigned to a worker with `hw_accel_types: ["nvenc"]`, the CPU codec is automatically swapped to its NVENC equivalent:
   - `libx265` → `hevc_nvenc`
   - `libx264` → `h264_nvenc`
   - `libsvtav1` → `av1_nvenc`
   - Incompatible `encoder_tune` values are stripped (NVENC only supports: `hq`, `ll`, `ull`, `lossless`)

2. **NVENC ffmpeg parameters** (`utils/ffmpeg.py`):
   - NVENC doesn't support `-crf`. When codec is `*_nvenc` and `bitrate_mode == "crf"`, uses `-rc vbr -cq <value> -b:v 0`
   - Default NVENC preset: `-preset p5 -tune hq`
   - Simplified CUDA hw accel: just `["-hwaccel", "cuda"]` (omits `-hwaccel_output_format cuda` to keep frames on CPU for filtering — simpler and works with all video filters)

3. **NVENC failure fallback** (`workers/transcode_worker.py`): If NVENC encoding fails (driver too old, no CUDA device, etc.), automatically retries with the CPU equivalent codec. Detects error patterns like `CUDA_ERROR`, `nvenc API version`, `Cannot load libcuda`.

4. **Jellyfin ffmpeg for vGPU compatibility** (`services/provisioning_service.py`): Vultr A16 is a virtual GPU with driver 550 (NVENC SDK 12.x). BtbN static ffmpeg needs SDK 13.0 (driver 570+). Provisioning now tests NVENC after installing static ffmpeg; if it fails, installs Jellyfin ffmpeg (compiled against SDK 12.x) as a drop-in replacement.

5. **NAS download fix** (`workers/transcode_worker.py`): When source was pulled from NAS via SSH, the output download tried to write to the NAS path locally (which doesn't exist on the controller machine). Fixed: downloads output to local staging (`/tmp/mediaflow/`), then uploads back to NAS via SSH, replaces original.

6. **UI enhancements** (frontend):
   - Global toast notification system (`AppState.swift` + `ContentView.swift`)
   - Queue status indicators with color coding and "no workers" warning banner (`ProcessingQueueView.swift`)
   - One-click recommendation queueing (`RecommendationsView.swift` + `RecommendationViewModel.swift`)
   - Cloud deploy error display on server cards (`ServerCardView.swift`)
   - Batch queue via `TranscodeService.create_jobs()` in recommendation service (ensures worker assignment + NVENC upgrade)

#### Key Lessons Learned (CRITICAL for future sessions)
- **Never install GPU drivers on Vultr vGPU instances.** The guest driver must match the hypervisor's vGPU manager version. Installing nvidia-driver-570 on a Vultr A16-16Q (which ships with 550) breaks the vGPU completely — `nvidia-smi` fails, `modprobe nvidia` returns "No such device", and you must destroy the instance.
- **Don't set `hw_accel="nvenc"` in auto-upgrade.** `-hwaccel cuda` enables CUDA decoding which crashes if the driver is broken. NVENC encoding works independently — just swap the codec and let CPU handle decoding.
- **Jellyfin ffmpeg is the solution for old NVENC SDK.** BtbN static ffmpeg is compiled against SDK 13.0 (needs driver 570+). Jellyfin ffmpeg is compiled against SDK 12.x (works with driver 535+). The provisioning service now tests NVENC and falls back to Jellyfin ffmpeg automatically.
- **Split long SSH command chains into discrete calls.** Chained commands with `&&` and `;` can silently swallow errors. Using separate `ssh.run_command()` calls is more reliable and easier to debug.

#### Commits (2026-02-11 session 4)
- `243ef84` — Auto-upgrade to NVENC GPU encoding when worker has NVIDIA GPU
- `88b01e8` — Fix NVENC GPU encoding: CPU fallback, Jellyfin ffmpeg for vGPU compatibility
- `fdd2af2` — Fix cloud transcode download: stage locally then upload back to NAS
- `9fbe094` — Add toast notifications, queue status indicators, and recommendation queueing
- `88f4cad` — Fix SSH timeout support and NVENC provisioning reliability

#### Remaining Issue Found at End of Session
- **Every cloud deploy so far has been running on CPU despite GPU being available.** Root cause: `SSHClient.run_command()` didn't accept a `timeout` kwarg, so the Jellyfin ffmpeg install in `provisioning_service.py` threw an exception and silently fell back. The static BtbN ffmpeg lists `hevc_nvenc` as an encoder but can't actually use it (SDK 13.0 vs driver 550's SDK 12.x). The fix (`88f4cad`) adds `timeout` support to `run_command()`. **Next deploy should verify Jellyfin ffmpeg installs and NVENC works at 500+ FPS.**

### Cloud Auto-Deploy on Queue — Implemented 2026-02-12

**Feature**: When transcode jobs are queued and no worker servers are online, automatically deploy a cloud GPU instance using saved defaults, then reassign the waiting jobs to it.

#### What Was Built
1. **Auto-deploy setting** (`cloud_auto_deploy_enabled` AppSetting, default: false)
   - New field on `CloudSettingsResponse` / `CloudSettingsUpdate` schemas
   - Read/write via `GET/PUT /api/cloud/settings`
   - Frontend toggle in Settings → Cloud GPU → AUTO-DEPLOY section

2. **Auto-deploy trigger** (`transcode_service.py → _maybe_auto_deploy_cloud()`):
   - After `create_jobs()` commits, checks if any jobs got `worker_server_id=None`
   - Guards: setting enabled, API key configured, no instance already provisioning, monthly spend cap not exceeded
   - Fires `deploy_cloud_gpu()` as background task
   - Broadcasts `cloud.auto_deploy_triggered` WebSocket event

3. **Job reassignment** (`cloud_provisioning_service.py → _reassign_unassigned_jobs()`):
   - Called at end of `deploy_cloud_gpu()` after worker goes online
   - Finds all `queued` jobs with `worker_server_id IS NULL`
   - Determines transfer mode, upgrades to NVENC, rebuilds ffmpeg command
   - Broadcasts `cloud.jobs_reassigned` WebSocket event

4. **Worker skip for non-local files** (`transcode_worker.py`):
   - `_process_queue()` now fetches up to 10 candidates
   - Skips unassigned jobs whose source isn't locally accessible (NAS paths)
   - Prevents immediate failure; jobs stay `queued` for cloud worker reassignment

5. **Deploy Cloud GPU button on queue banner** (`ProcessingQueueView.swift`):
   - When no workers online and Vultr API key configured, warning banner shows "Deploy Cloud GPU" button
   - After clicking, banner switches to blue "Cloud GPU is building — queued jobs will start automatically when ready." with spinner
   - WebSocket events clear deploying state on success/failure

#### Files Modified
- `backend/app/schemas/cloud.py` — `auto_deploy_enabled` field
- `backend/app/api/cloud.py` — read/write setting
- `backend/app/services/transcode_service.py` — `_maybe_auto_deploy_cloud()` + trigger after `create_jobs()`
- `backend/app/services/cloud_provisioning_service.py` — `_reassign_unassigned_jobs()` at end of deploy
- `backend/app/workers/transcode_worker.py` — skip non-local unassigned jobs
- `frontend/.../Models/WorkerServer.swift` — `autoDeployEnabled` on settings models
- `frontend/.../Views/Settings/SettingsView.swift` — AUTO-DEPLOY toggle card
- `frontend/.../Views/Transcode/ProcessingQueueView.swift` — Deploy Cloud GPU button + building banner
- `frontend/.../ViewModels/TranscodeViewModel.swift` — `cloudApiKeyConfigured`, `isDeployingCloud`, cloud WebSocket subs
- `frontend/.../ViewModels/ServerManagementViewModel.swift` — `cloud.auto_deploy_triggered` + `cloud.jobs_reassigned` subscriptions
- `frontend/.../Views/Servers/ServerManagementView.swift` — auto-deploy toast

#### New WebSocket Events
- `cloud.auto_deploy_triggered` — {job_count, plan, region}
- `cloud.jobs_reassigned` — {server_id, job_count}

#### New AppSettings Key
- `cloud_auto_deploy_enabled` — "true"/"false" (default "false")

#### Commits
- `fe495c9` — Add cloud auto-deploy when no workers available for queued jobs

### Current Path Mappings (stored in app_settings)
- `/share/ZFS18_DATA/Media` → `/Volumes/media` (TrueNAS SMB mount)

### Curated GPU Plans (in ALLOWED_GPU_PLANS)
| Display Name | Plan ID | Hourly |
|---|---|---|
| A16 1× (16GB) | vcg-a16-6c-64g-16vram | ~$0.47/hr |
| A40 1/3 (16GB) | vcg-a40-8c-40g-16vram | ~$0.58/hr |
| A40 1/2 (24GB) | vcg-a40-12c-60g-24vram | ~$0.86/hr |

---

## Known Issues & Tech Debt

1. **SettingsView.swift:187** — Uses deprecated `onChange(of:perform:)` API. Should update to zero-parameter closure variant for macOS 14+.

2. **NSPanel workaround** — macOS SPM apps have broken keyboard focus in `.sheet()` modals. AddServerSheet, SettingsView SSH form, CloudDeployPanel, and CloudAPIKeyPanel use NSPanel with NSHostingView as a workaround. Requirements: `.nonactivatingPanel` in styleMask, `becomesKeyOnlyIfNeeded = false`, `NSApp.activate(ignoringOtherApps: true)`.

3. **CodingKeys + convertFromSnakeCase** — APIClient uses automatic snake_case conversion. Never add explicit CodingKeys with snake_case raw values or it double-converts (causes keyNotFound errors).

4. **SSH login_timeout** — Set to 15 seconds in SSHClient._connect_kwargs(). Without this, connections to unreachable hosts hang indefinitely. Cloud connections use 30s in `run_command_streaming()`.

5. **SQLite migrations** — Uses ADD COLUMN with try/catch (SQLite doesn't support full ALTER TABLE). New columns go in the MIGRATIONS list in database.py as `(table, column, type_definition)` tuples.

6. **Actor isolation** — Don't mark service classes as `@MainActor` if ViewModels need to call their init synchronously. ViewModels are already `@MainActor`.

7. **Column resize direction** — When resize divider is on the LEFT edge of a column, use `dragStartWidth - translation.width` (subtract, not add).

8. **UniFi IDS/IPS blocks SSH** — UniFi "Intrusion Prevention" flags repeated SSH attempts as "ET SCAN Potential SSH Scan OUTBOUND" (Signature ID 2003068). Must suppress this signature in UniFi Settings > Security > Threat Management on each network that runs MediaFlow.

9. **Multi-computer Dropbox sync** — User accesses project from multiple computers via Dropbox. SSH keys and file paths may differ between machines. Path mappings and SSH key paths are stored in the SQLite DB, so they persist per-machine (each machine has its own `mediaflow.db`).

---

## Dependencies

### Backend (Python)
```
fastapi>=0.109.0
uvicorn[standard]>=0.27.0
sqlalchemy[asyncio]>=2.0.25
aiosqlite>=0.19.0
httpx>=0.26.0
pydantic>=2.5.0
pydantic-settings>=2.1.0
python-dotenv>=1.0.0
alembic>=1.13.0
cryptography>=41.0.0
aiofiles>=23.2.0
python-multipart>=0.0.6
websockets>=12.0
asyncssh>=2.14.0
```

### Frontend (Swift)
- Swift 5.9+, macOS 14+ (Sonoma)
- No external Swift package dependencies — pure SwiftUI + AppKit
- Built via `swift build` (SPM), not Xcode

### System
- FFmpeg + FFprobe (auto-detected from PATH, or auto-installed on remote workers)
- Python 3.11+

---

## What to Work On Next

### Completed (2026-02-11)
- ~~Test full cloud transcode cycle~~ — **DONE.** End-to-end working: Deploy Vultr GPU → upload from NAS → hevc_nvenc at 561 FPS → download → upload back to NAS → replace original.
- ~~Cloud GPU provisioning~~ — **DONE.** Auto-installs ffmpeg, tests NVENC, falls back to Jellyfin ffmpeg for vGPU SDK compatibility.
- ~~NVENC auto-upgrade~~ — **DONE.** CPU codec → GPU codec when worker has NVENC capability.

### High Priority
1. **Path mappings UI** — Currently set via direct DB insert. Need a Settings panel for configuring NAS path mappings (`source_prefix` → `target_prefix`).
2. **Bulk transcode from library** — Allow selecting multiple items in the library browser and queueing them for transcode in one action (the recommendation batch-queue path works, but direct library selection → transcode is not yet wired).
3. ~~**Cloud worker auto-deploy on queue**~~ — **DONE** (2026-02-12). See below.

### Medium Priority
4. **Custom tagging system frontend** — Backend model (CustomTag, MediaTag) exists. Need UI for creating tags, applying to media items, filtering by tags.
5. **Email notification UI** — Backend NotificationService exists. Need Settings panel for configuring email (SMTP) and enabling per-event notifications.
6. **Batch metadata editing UI** — Need modal for bulk-updating titles, genres, collections on selected media items.
7. **Collection builder UI** — Auto-create Plex collections from filter criteria (e.g., "All Dolby Atmos Movies").
8. **SettingsView deprecation fix** — Update onChange(of:perform:) to new syntax.

### Low Priority
9. **PDF health reports** — Export library analysis as PDF.
10. **Scheduling UI** — Configure transcode processing hours (e.g., overnight only).
11. **App icon** — Currently using default Xcode icon.
12. **macOS push notifications** — System notification center integration.
