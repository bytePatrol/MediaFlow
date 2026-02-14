import Foundation

// MARK: - Data Models

struct HelpTopic: Identifiable {
    let id: String
    let category: HelpCategory
    let icon: String
    let title: String
    let summary: String
    let sections: [HelpSection]
    let searchKeywords: [String]
}

enum HelpCategory: String, CaseIterable {
    case gettingStarted = "Getting Started"
    case features = "Features"
    case advanced = "Advanced"
    case reference = "Reference"

    var icon: String {
        switch self {
        case .gettingStarted: return "sparkles"
        case .features: return "square.grid.2x2"
        case .advanced: return "gearshape.2"
        case .reference: return "book.closed"
        }
    }

    var color: String {
        switch self {
        case .gettingStarted: return "mfPrimary"
        case .features: return "mfSuccess"
        case .advanced: return "mfWarning"
        case .reference: return "mfInfo"
        }
    }
}

struct HelpSection {
    let title: String
    let content: HelpSectionContent
}

enum HelpSectionContent {
    case text(String)
    case steps([HelpStep])
    case tips([HelpTip])
    case shortcuts([HelpShortcut])
    case troubleshoot([TroubleshootItem])
    case features([FeatureItem])
}

struct HelpStep: Identifiable {
    let id = UUID()
    let number: Int
    let title: String
    let description: String
}

struct HelpTip: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    let style: HelpTipStyle
}

enum HelpTipStyle {
    case info, warning, success
}

struct HelpShortcut: Identifiable {
    let id = UUID()
    let keys: String
    let description: String
}

struct TroubleshootItem: Identifiable {
    let id = UUID()
    let problem: String
    let cause: String
    let solution: String
}

struct FeatureItem: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let description: String
}

// MARK: - All Topics

enum HelpContent {
    static let allTopics: [HelpTopic] = [
        // MARK: Getting Started

        HelpTopic(
            id: "welcome",
            category: .gettingStarted,
            icon: "hand.wave",
            title: "Welcome to MediaFlow",
            summary: "Overview of what MediaFlow does and how to get started",
            sections: [
                HelpSection(title: "What is MediaFlow?", content: .text(
                    "MediaFlow is a macOS app that optimizes your Plex media library by analyzing your files and intelligently transcoding them to save storage space while maintaining quality. It supports distributed transcoding across multiple workers, including cloud GPU instances."
                )),
                HelpSection(title: "Key Capabilities", content: .features([
                    FeatureItem(icon: "brain", title: "Intelligent Analysis", description: "Automatically analyzes your media files and recommends optimal transcode settings based on codec efficiency, resolution, and bitrate."),
                    FeatureItem(icon: "server.rack", title: "Distributed Transcoding", description: "Spread transcoding across local machines, remote SSH workers, and cloud GPU instances for maximum throughput."),
                    FeatureItem(icon: "chart.bar.xaxis", title: "Analytics & Insights", description: "Track storage savings, transcode performance, and library health with detailed charts and predictions."),
                    FeatureItem(icon: "bell", title: "Notifications", description: "Get notified via email, Discord, Slack, Telegram, webhooks, or native macOS notifications."),
                ])),
                HelpSection(title: "First Steps", content: .steps([
                    HelpStep(number: 1, title: "Connect to Plex", description: "Sign in with your Plex account to discover your servers and libraries."),
                    HelpStep(number: 2, title: "Add a Worker", description: "Set up at least one transcode worker — your local machine works great to start."),
                    HelpStep(number: 3, title: "Run Analysis", description: "Let the Intelligence system analyze your library and generate recommendations."),
                    HelpStep(number: 4, title: "Start Transcoding", description: "Review recommendations and queue up transcode jobs to optimize your library."),
                ])),
            ],
            searchKeywords: ["overview", "introduction", "start", "setup", "first", "begin", "what is"]
        ),

        HelpTopic(
            id: "connecting-plex",
            category: .gettingStarted,
            icon: "link",
            title: "Connecting to Plex",
            summary: "Sign in via OAuth, discover servers, and sync your libraries",
            sections: [
                HelpSection(title: "Sign In with Plex", content: .steps([
                    HelpStep(number: 1, title: "Open Settings", description: "Navigate to Settings (⌘7) and find the Plex Account section."),
                    HelpStep(number: 2, title: "Click Sign In", description: "Click the \"Sign In with Plex\" button. A browser window will open for Plex OAuth authentication."),
                    HelpStep(number: 3, title: "Authorize MediaFlow", description: "Sign in to your Plex account in the browser and authorize MediaFlow to access your servers."),
                    HelpStep(number: 4, title: "Server Discovery", description: "After authorization, MediaFlow automatically discovers your Plex servers and syncs their libraries."),
                ])),
                HelpSection(title: "Library Sync", content: .text(
                    "Once connected, MediaFlow fetches all movie and TV show libraries from your Plex server. The initial sync imports metadata, file paths, and codec information for every media item. Subsequent syncs are incremental and only fetch changes."
                )),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "Your Plex server must be running and reachable from this Mac for the connection to succeed.", style: .info),
                    HelpTip(icon: "arrow.clockwise", text: "If your libraries appear empty after connecting, try clicking the sync button on the Library page to trigger a fresh import.", style: .info),
                    HelpTip(icon: "lock.shield", text: "MediaFlow uses Plex's official OAuth flow — your password is never stored locally.", style: .success),
                ])),
            ],
            searchKeywords: ["plex", "oauth", "sign in", "login", "server", "connect", "library", "sync", "discover"]
        ),

        HelpTopic(
            id: "adding-workers",
            category: .gettingStarted,
            icon: "plus.circle",
            title: "Adding Workers",
            summary: "Set up local, remote SSH, or cloud GPU transcode workers",
            sections: [
                HelpSection(title: "What Are Workers?", content: .text(
                    "Workers are machines that perform the actual transcoding. MediaFlow supports three types: your local machine, remote machines accessed via SSH, and cloud GPU instances provisioned on-demand. You need at least one worker to start transcoding."
                )),
                HelpSection(title: "Add a Local Worker", content: .steps([
                    HelpStep(number: 1, title: "Go to Servers", description: "Navigate to the Servers page (⌘4)."),
                    HelpStep(number: 2, title: "Click Add Server", description: "Click the \"+\" button in the top-right corner."),
                    HelpStep(number: 3, title: "Enter Details", description: "Set the hostname to \"localhost\" or \"127.0.0.1\". Choose \"Local\" as the connection type."),
                    HelpStep(number: 4, title: "Set FFmpeg Path", description: "Provide the path to your ffmpeg binary (e.g., /usr/local/bin/ffmpeg or /opt/homebrew/bin/ffmpeg)."),
                ])),
                HelpSection(title: "Add a Remote SSH Worker", content: .steps([
                    HelpStep(number: 1, title: "Ensure SSH Access", description: "The remote machine must be accessible via SSH with key-based authentication."),
                    HelpStep(number: 2, title: "Add Server", description: "Click \"+\" on the Servers page and choose \"SSH\" as the connection type."),
                    HelpStep(number: 3, title: "Configure SSH", description: "Enter the hostname/IP, SSH port (default 22), username, and path to your SSH private key."),
                    HelpStep(number: 4, title: "Set FFmpeg Path", description: "Provide the path to ffmpeg on the remote machine."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "bolt.fill", text: "Workers with NVENC GPU support are automatically detected and used for hardware-accelerated encoding.", style: .success),
                    HelpTip(icon: "exclamationmark.triangle", text: "Remote workers need ffmpeg installed. MediaFlow does not install it automatically.", style: .warning),
                ])),
            ],
            searchKeywords: ["worker", "server", "add", "local", "ssh", "remote", "ffmpeg", "setup", "gpu"]
        ),

        HelpTopic(
            id: "first-analysis",
            category: .gettingStarted,
            icon: "magnifyingglass",
            title: "Running Your First Analysis",
            summary: "Analyze your library and get intelligent recommendations",
            sections: [
                HelpSection(title: "How Analysis Works", content: .text(
                    "The Intelligence system scans your media library and evaluates each file's codec, resolution, bitrate, and container format. It compares these against optimal targets and generates recommendations for files that would benefit from transcoding. The system learns from your library's actual compression ratios over time."
                )),
                HelpSection(title: "Start an Analysis", content: .steps([
                    HelpStep(number: 1, title: "Go to Intelligence", description: "Navigate to the Intelligence page (⌘6)."),
                    HelpStep(number: 2, title: "Click Analyze", description: "Click the \"Analyze Library\" button. The system will scan all media items."),
                    HelpStep(number: 3, title: "Review Recommendations", description: "Once complete, recommendations appear sorted by priority — highest impact items first."),
                    HelpStep(number: 4, title: "Queue Transcodes", description: "Click \"Queue\" on individual recommendations, or use \"Queue All\" to batch-queue everything."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "clock", text: "The first analysis may take a minute for large libraries. Subsequent analyses are faster since only new or changed items are re-evaluated.", style: .info),
                    HelpTip(icon: "brain", text: "Auto-analyze can be enabled in Settings to run analysis automatically when new media is detected.", style: .info),
                    HelpTip(icon: "arrow.up.arrow.down", text: "Recommendations are scored by priority: estimated space savings weighted by file size and codec inefficiency.", style: .info),
                ])),
            ],
            searchKeywords: ["analysis", "analyze", "intelligence", "recommendation", "scan", "first", "queue"]
        ),

        // MARK: Features

        HelpTopic(
            id: "library-management",
            category: .features,
            icon: "books.vertical",
            title: "Library Management",
            summary: "Browse, filter, and manage your media collection",
            sections: [
                HelpSection(title: "Overview", content: .text(
                    "The Library page (⌘1) is your central view of all media synced from Plex. It shows every movie and TV show episode with codec details, resolution, file size, and transcode status."
                )),
                HelpSection(title: "Features", content: .features([
                    FeatureItem(icon: "line.3.horizontal.decrease", title: "Filtering", description: "Filter by resolution (4K, 1080p, 720p, SD), codec (H.264, H.265, etc.), library, and transcode status using the filter pill bar."),
                    FeatureItem(icon: "arrow.up.arrow.down", title: "Sorting", description: "Sort by title, file size, resolution, codec, or date added. Click column headers to toggle sort direction."),
                    FeatureItem(icon: "magnifyingglass", title: "Search", description: "Use the search bar to find specific titles across all libraries."),
                    FeatureItem(icon: "rectangle.stack", title: "Collections", description: "Build custom collections of media items for batch operations."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "Click on any media item to see detailed file information including all audio and subtitle tracks.", style: .info),
                    HelpTip(icon: "arrow.clockwise", text: "Use the sync button to refresh library data from Plex if items appear outdated.", style: .info),
                ])),
            ],
            searchKeywords: ["library", "browse", "filter", "search", "sort", "collection", "media", "movies", "tv"]
        ),

        HelpTopic(
            id: "transcoding",
            category: .features,
            icon: "gearshape.2",
            title: "Transcoding",
            summary: "Transcode presets, queue management, and monitoring progress",
            sections: [
                HelpSection(title: "How Transcoding Works", content: .text(
                    "MediaFlow transcodes media files using ffmpeg on your configured workers. Files are pulled from your Plex library (via NAS or local path), transcoded according to the selected preset, and the output replaces the original file. Plex automatically detects the updated file."
                )),
                HelpSection(title: "Built-in Presets", content: .features([
                    FeatureItem(icon: "dial.medium", title: "Balanced", description: "H.265 with CRF 22. Good balance of quality and file size reduction."),
                    FeatureItem(icon: "internaldrive", title: "Storage Saver", description: "H.265 with CRF 26. Maximum space savings with acceptable quality loss."),
                    FeatureItem(icon: "iphone", title: "Mobile Optimized", description: "H.264 at 720p with CRF 23. Small files optimized for mobile streaming."),
                    FeatureItem(icon: "star", title: "Ultra Fidelity", description: "H.265 with CRF 18. Near-lossless quality for archival purposes."),
                ])),
                HelpSection(title: "Queue Management", content: .text(
                    "The Processing page (⌘3) shows all queued, active, and completed transcode jobs. Active jobs display real-time progress with ETA. You can pause, cancel, or re-queue jobs. Workers are assigned automatically based on availability and capability scoring."
                )),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "bolt.fill", text: "Workers with NVENC GPUs automatically use hardware encoding for dramatically faster transcodes.", style: .success),
                    HelpTip(icon: "exclamationmark.triangle", text: "If a GPU encode fails (driver issue), MediaFlow automatically retries with CPU encoding.", style: .warning),
                ])),
            ],
            searchKeywords: ["transcode", "encode", "preset", "queue", "ffmpeg", "h265", "h264", "hevc", "processing", "progress"]
        ),

        HelpTopic(
            id: "quick-transcode",
            category: .features,
            icon: "bolt.fill",
            title: "Quick Transcode",
            summary: "Transcode local files outside your Plex library",
            sections: [
                HelpSection(title: "Overview", content: .text(
                    "Quick Transcode (⌘2) lets you transcode any local video file — it doesn't have to be in your Plex library. This is useful for processing files before adding them to Plex, or for general-purpose transcoding tasks."
                )),
                HelpSection(title: "How to Use", content: .steps([
                    HelpStep(number: 1, title: "Select Input File", description: "Click \"Choose File\" or drag and drop a video file onto the input area."),
                    HelpStep(number: 2, title: "Choose Output Location", description: "Select where to save the transcoded file."),
                    HelpStep(number: 3, title: "Pick a Preset", description: "Select a transcode preset or configure custom settings."),
                    HelpStep(number: 4, title: "Start Transcode", description: "Click \"Start\" to begin. Progress is shown in real-time."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "Quick Transcode uses the same worker system as library transcoding — your fastest available worker is used automatically.", style: .info),
                ])),
            ],
            searchKeywords: ["quick", "manual", "local", "file", "drag", "drop", "outside", "plex"]
        ),

        HelpTopic(
            id: "intelligence",
            category: .features,
            icon: "brain",
            title: "Intelligence & Recommendations",
            summary: "AI-powered analysis, recommendation types, and batch queuing",
            sections: [
                HelpSection(title: "How Intelligence Works", content: .text(
                    "The Intelligence system evaluates your media files against optimal encoding targets. It considers codec efficiency (H.264 vs H.265), bitrate relative to resolution, audio codec optimization, container format, and HDR metadata. Recommendations are prioritized by estimated space savings."
                )),
                HelpSection(title: "Recommendation Types", content: .features([
                    FeatureItem(icon: "video", title: "Video Codec", description: "Suggests re-encoding from less efficient codecs (e.g., H.264 → H.265) for significant space savings."),
                    FeatureItem(icon: "speaker.wave.3", title: "Audio Optimization", description: "Recommends audio codec changes (e.g., PCM/DTS → AAC) to reduce file size."),
                    FeatureItem(icon: "doc", title: "Container Format", description: "Suggests remuxing to a more compatible container (e.g., AVI → MKV) without re-encoding."),
                    FeatureItem(icon: "4k.tv", title: "HDR Preservation", description: "Identifies HDR content and ensures transcode settings preserve HDR metadata."),
                    FeatureItem(icon: "square.stack.3d.up", title: "Batch Operations", description: "Groups similar recommendations for efficient batch processing."),
                ])),
                HelpSection(title: "Learned Ratios", content: .text(
                    "As you transcode more files, MediaFlow learns actual compression ratios for your content. These learned ratios improve the accuracy of space-saving estimates over time, making recommendations increasingly precise."
                )),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "slider.horizontal.3", text: "Adjust the minimum savings threshold in Settings to control which recommendations appear. Higher thresholds show only the most impactful items.", style: .info),
                    HelpTip(icon: "clock", text: "Enable auto-analyze in Settings to automatically scan for new recommendations when library changes are detected.", style: .success),
                ])),
            ],
            searchKeywords: ["intelligence", "recommendation", "analysis", "codec", "savings", "learned", "ratio", "priority", "batch", "auto"]
        ),

        HelpTopic(
            id: "analytics",
            category: .features,
            icon: "chart.bar.xaxis",
            title: "Analytics Dashboard",
            summary: "Health score, trends, storage predictions, and PDF export",
            sections: [
                HelpSection(title: "Overview", content: .text(
                    "The Analytics Dashboard (⌘5) gives you a comprehensive view of your library's health, transcode history, and storage trends. It helps you understand the impact of your optimization work and predict future storage needs."
                )),
                HelpSection(title: "Dashboard Sections", content: .features([
                    FeatureItem(icon: "heart.text.square", title: "Library Health Score", description: "An overall score (0-100) based on codec efficiency, resolution distribution, and optimization coverage across your library."),
                    FeatureItem(icon: "chart.line.uptrend.xyaxis", title: "Storage Trends", description: "Charts showing storage usage over time, with projections based on your current transcoding pace."),
                    FeatureItem(icon: "clock.arrow.circlepath", title: "Transcode History", description: "Timeline of completed transcodes with speed, space saved, and worker used for each job."),
                    FeatureItem(icon: "arrow.down.doc", title: "PDF Export", description: "Export a detailed analytics report as a PDF for sharing or archival purposes."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "The health score updates after each transcode completes and after library syncs.", style: .info),
                ])),
            ],
            searchKeywords: ["analytics", "dashboard", "health", "score", "chart", "storage", "trend", "prediction", "pdf", "export", "report"]
        ),

        HelpTopic(
            id: "scheduling",
            category: .features,
            icon: "calendar.badge.clock",
            title: "Scheduling",
            summary: "Configure active hours, day-of-week rules, and per-job scheduling",
            sections: [
                HelpSection(title: "Overview", content: .text(
                    "Scheduling lets you control when MediaFlow runs transcode jobs. This is useful for avoiding resource contention during peak usage hours or limiting transcoding to off-peak times when electricity is cheaper."
                )),
                HelpSection(title: "Configuration", content: .features([
                    FeatureItem(icon: "clock", title: "Active Hours", description: "Set a daily time window during which transcoding is allowed (e.g., 11 PM – 7 AM)."),
                    FeatureItem(icon: "calendar", title: "Day-of-Week Rules", description: "Enable or disable transcoding on specific days of the week."),
                    FeatureItem(icon: "gearshape", title: "Per-Job Scheduling", description: "Override global scheduling for individual jobs that need to run immediately or at specific times."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "Scheduling is configured in Settings (⌘7) under the Scheduling section.", style: .info),
                    HelpTip(icon: "bolt.fill", text: "Jobs queued outside active hours will wait until the next active window to start.", style: .info),
                ])),
            ],
            searchKeywords: ["schedule", "scheduling", "active hours", "time", "day", "week", "off-peak", "window"]
        ),

        HelpTopic(
            id: "notifications",
            category: .features,
            icon: "bell",
            title: "Notifications",
            summary: "Email, webhook, Discord, Slack, Telegram, and macOS native alerts",
            sections: [
                HelpSection(title: "Supported Channels", content: .features([
                    FeatureItem(icon: "envelope", title: "Email", description: "SMTP email notifications for job completion, errors, and daily digest reports."),
                    FeatureItem(icon: "arrow.up.forward.app", title: "Webhooks", description: "Send HTTP POST payloads to any URL — useful for custom integrations."),
                    FeatureItem(icon: "bubble.left.and.bubble.right", title: "Discord", description: "Post notifications to a Discord channel via webhook URL."),
                    FeatureItem(icon: "number", title: "Slack", description: "Send notifications to a Slack channel via incoming webhook."),
                    FeatureItem(icon: "paperplane", title: "Telegram", description: "Send notifications to a Telegram chat via bot token."),
                    FeatureItem(icon: "bell.badge", title: "macOS Native", description: "Native macOS notification center alerts for immediate local feedback."),
                ])),
                HelpSection(title: "Setup", content: .steps([
                    HelpStep(number: 1, title: "Open Settings", description: "Go to Settings (⌘7) and find the Notifications section."),
                    HelpStep(number: 2, title: "Enable Channels", description: "Toggle on the notification channels you want to use."),
                    HelpStep(number: 3, title: "Configure Credentials", description: "Enter the required credentials for each channel (SMTP server, webhook URL, bot token, etc.)."),
                    HelpStep(number: 4, title: "Test", description: "Use the \"Send Test\" button to verify each channel is working correctly."),
                ])),
            ],
            searchKeywords: ["notification", "email", "webhook", "discord", "slack", "telegram", "alert", "notify", "smtp"]
        ),

        // MARK: Advanced

        HelpTopic(
            id: "cloud-gpu",
            category: .advanced,
            icon: "cloud",
            title: "Cloud GPU Workers",
            summary: "Vultr provisioning, cost tracking, and auto-teardown",
            sections: [
                HelpSection(title: "Overview", content: .text(
                    "MediaFlow can provision GPU-accelerated cloud instances on Vultr for high-speed NVENC transcoding. Instances are created on-demand, used for transcoding, and automatically torn down when idle to minimize costs."
                )),
                HelpSection(title: "Setup", content: .steps([
                    HelpStep(number: 1, title: "Add Vultr API Key", description: "Go to Settings (⌘7) and enter your Vultr API key in the Cloud GPU section."),
                    HelpStep(number: 2, title: "Deploy a Cloud Worker", description: "On the Servers page (⌘4), click \"Deploy Cloud Worker\" and select your preferred GPU tier and region."),
                    HelpStep(number: 3, title: "Wait for Provisioning", description: "MediaFlow creates the instance, installs dependencies, and registers it as a worker. Progress is shown in real-time."),
                    HelpStep(number: 4, title: "Start Transcoding", description: "The cloud worker is now available for job assignment alongside your local workers."),
                ])),
                HelpSection(title: "Cost Management", content: .features([
                    FeatureItem(icon: "dollarsign.circle", title: "Cost Tracking", description: "Per-instance and per-job costs are tracked and displayed on the Analytics dashboard."),
                    FeatureItem(icon: "clock.badge.xmark", title: "Idle Timeout", description: "Cloud workers are automatically destroyed after a configurable idle period (default: 15 minutes)."),
                    FeatureItem(icon: "exclamationmark.shield", title: "Spend Cap", description: "Set a maximum monthly spend to prevent runaway costs. Workers are stopped when the cap is reached."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "exclamationmark.triangle", text: "Never manually update NVIDIA drivers on Vultr GPU instances. The vGPU guest driver must match the hypervisor version — changing it will permanently break GPU access.", style: .warning),
                    HelpTip(icon: "info.circle", text: "Cloud workers use Jellyfin ffmpeg for maximum NVENC compatibility with Vultr's driver version.", style: .info),
                ])),
            ],
            searchKeywords: ["cloud", "gpu", "vultr", "provision", "cost", "teardown", "idle", "spend", "nvenc", "deploy"]
        ),

        HelpTopic(
            id: "distributed-transcoding",
            category: .advanced,
            icon: "network",
            title: "Distributed Transcoding",
            summary: "Multi-worker scoring, failover, and NVENC acceleration",
            sections: [
                HelpSection(title: "How Worker Selection Works", content: .text(
                    "When a transcode job is ready to run, MediaFlow scores all available workers based on current load, hardware capabilities (CPU vs GPU), historical performance, and network proximity. The highest-scoring worker is assigned the job."
                )),
                HelpSection(title: "Key Concepts", content: .features([
                    FeatureItem(icon: "gauge.with.dots.needle.33percent", title: "Worker Scoring", description: "Workers are ranked by a composite score factoring in GPU availability, current utilization, historical speed, and connection quality."),
                    FeatureItem(icon: "arrow.triangle.2.circlepath", title: "Automatic Failover", description: "If a worker fails mid-transcode, the job is automatically reassigned to another available worker."),
                    FeatureItem(icon: "bolt.fill", title: "NVENC Auto-Upgrade", description: "When a worker has NVENC GPU support, CPU codecs are automatically upgraded to GPU equivalents (e.g., libx265 → hevc_nvenc)."),
                    FeatureItem(icon: "arrow.down.to.line", title: "NVENC Fallback", description: "If GPU encoding fails (driver issue), the job automatically retries with CPU encoding."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "Worker health checks run automatically. Unhealthy workers are excluded from job assignment until they recover.", style: .info),
                    HelpTip(icon: "server.rack", text: "You can view detailed worker stats and comparison on the Servers page (⌘4).", style: .info),
                ])),
            ],
            searchKeywords: ["distributed", "worker", "scoring", "failover", "nvenc", "gpu", "multi", "parallel", "load", "balance"]
        ),

        HelpTopic(
            id: "custom-presets",
            category: .advanced,
            icon: "slider.horizontal.3",
            title: "Custom Presets",
            summary: "Create and edit transcode presets with full codec control",
            sections: [
                HelpSection(title: "Overview", content: .text(
                    "While MediaFlow includes four built-in presets, you can create custom presets with full control over video codec, audio codec, CRF/bitrate, resolution scaling, and more. Custom presets appear alongside built-in ones when queuing transcodes."
                )),
                HelpSection(title: "Preset Settings", content: .features([
                    FeatureItem(icon: "video", title: "Video Codec", description: "Choose from H.264, H.265/HEVC, AV1, VP9, and their hardware-accelerated variants."),
                    FeatureItem(icon: "speaker.wave.3", title: "Audio Codec", description: "Select AAC, Opus, AC3, EAC3, or copy (passthrough) for audio encoding."),
                    FeatureItem(icon: "dial.medium", title: "Quality Mode", description: "Use CRF (constant quality) or target bitrate mode. CRF is recommended for most use cases."),
                    FeatureItem(icon: "arrow.up.left.and.arrow.down.right", title: "Resolution", description: "Optionally downscale to a target resolution (e.g., 4K → 1080p)."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "CRF values: lower = higher quality, larger files. Typical range: 18 (high quality) to 28 (small files). 22-23 is a good default.", style: .info),
                    HelpTip(icon: "exclamationmark.triangle", text: "NVENC GPUs don't support CRF directly. MediaFlow automatically converts to equivalent VBR settings when a GPU worker is used.", style: .warning),
                ])),
            ],
            searchKeywords: ["preset", "custom", "create", "codec", "crf", "bitrate", "resolution", "quality", "settings", "h264", "h265", "av1"]
        ),

        // MARK: Reference

        HelpTopic(
            id: "keyboard-shortcuts",
            category: .reference,
            icon: "keyboard",
            title: "Keyboard Shortcuts",
            summary: "Complete list of keyboard shortcuts",
            sections: [
                HelpSection(title: "Navigation", content: .shortcuts([
                    HelpShortcut(keys: "⌘1", description: "Library"),
                    HelpShortcut(keys: "⌘2", description: "Quick Transcode"),
                    HelpShortcut(keys: "⌘3", description: "Processing"),
                    HelpShortcut(keys: "⌘4", description: "Servers"),
                    HelpShortcut(keys: "⌘5", description: "Analytics"),
                    HelpShortcut(keys: "⌘6", description: "Intelligence"),
                    HelpShortcut(keys: "⌘7", description: "Settings"),
                    HelpShortcut(keys: "⌘8", description: "Logs"),
                    HelpShortcut(keys: "⌘9", description: "Help"),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "All navigation shortcuts use ⌘ (Command) plus a number key. The number corresponds to the item's position in the sidebar.", style: .info),
                ])),
            ],
            searchKeywords: ["keyboard", "shortcut", "hotkey", "command", "cmd", "keybinding", "shortcut"]
        ),

        HelpTopic(
            id: "troubleshooting",
            category: .reference,
            icon: "wrench.and.screwdriver",
            title: "Troubleshooting",
            summary: "Common issues and their solutions",
            sections: [
                HelpSection(title: "Common Issues", content: .troubleshoot([
                    TroubleshootItem(
                        problem: "Backend shows \"Offline\" in the sidebar",
                        cause: "The FastAPI backend server is not running or not reachable on port 9876.",
                        solution: "Start the backend with ./run.sh --backend-only or cd backend && source venv/bin/activate && uvicorn app.main:app --port 9876. Check that nothing else is using port 9876."
                    ),
                    TroubleshootItem(
                        problem: "Plex libraries appear empty after connecting",
                        cause: "The initial library sync may not have completed, or the Plex server was temporarily unreachable during sync.",
                        solution: "Go to the Library page and click the sync/refresh button. Ensure your Plex server is running and accessible from this Mac."
                    ),
                    TroubleshootItem(
                        problem: "Transcode jobs stuck in \"Queued\" status",
                        cause: "No workers are available, all workers are busy, or scheduling rules are blocking execution.",
                        solution: "Check the Servers page (⌘4) to verify at least one worker is online and healthy. Check Settings (⌘7) to ensure current time is within active hours."
                    ),
                    TroubleshootItem(
                        problem: "NVENC encoding fails on cloud worker",
                        cause: "The NVENC SDK version bundled with the static ffmpeg build may be incompatible with the Vultr vGPU driver.",
                        solution: "MediaFlow automatically falls back to CPU encoding. If persistent, the provisioning system will install Jellyfin ffmpeg (compatible with older NVENC SDK). Check worker logs for details."
                    ),
                    TroubleshootItem(
                        problem: "Transcoded file is larger than the original",
                        cause: "The source file was already well-optimized, or the CRF value is too low (high quality) for the content type.",
                        solution: "Try a higher CRF value (e.g., 24-26) or use the Storage Saver preset. Some already-efficient files may not benefit from re-encoding."
                    ),
                    TroubleshootItem(
                        problem: "SSH worker connection fails",
                        cause: "SSH key authentication failed, the remote host is unreachable, or the SSH port is blocked.",
                        solution: "Verify you can SSH to the worker manually: ssh -i /path/to/key user@host. Check that the SSH key path, username, and port in MediaFlow match your SSH config."
                    ),
                    TroubleshootItem(
                        problem: "Analysis shows no recommendations",
                        cause: "Your library is already well-optimized, or the minimum savings threshold is set too high.",
                        solution: "Lower the minimum savings threshold in Settings (⌘7) under Intelligence. Even optimized libraries may have opportunities with a lower threshold."
                    ),
                    TroubleshootItem(
                        problem: "Notifications aren't being delivered",
                        cause: "The notification channel is misconfigured, or credentials are invalid.",
                        solution: "Go to Settings (⌘7) and use the \"Send Test\" button for each configured channel. Check SMTP credentials, webhook URLs, or bot tokens for typos."
                    ),
                ])),
            ],
            searchKeywords: ["troubleshoot", "problem", "issue", "error", "fix", "help", "debug", "not working", "stuck", "fail", "offline"]
        ),
    ]
}
