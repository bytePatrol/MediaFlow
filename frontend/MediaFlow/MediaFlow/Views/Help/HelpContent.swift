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
                    "MediaFlow is a macOS app that optimizes your Plex media library by analyzing your files and intelligently transcoding them to save storage space while maintaining quality. It supports distributed transcoding across multiple workers including cloud GPU instances, smart automation, VMAF quality validation, and premium analytics."
                )),
                HelpSection(title: "Key Capabilities", content: .features([
                    FeatureItem(icon: "brain", title: "Intelligent Analysis", description: "Automatically analyzes your media files and recommends optimal transcode settings. Learns from your preferences and improves over time."),
                    FeatureItem(icon: "server.rack", title: "Distributed Transcoding", description: "Spread transcoding across local machines, remote SSH workers, and cloud GPU instances for maximum throughput."),
                    FeatureItem(icon: "gearshape.arrow.triangle.2.circlepath", title: "Smart Automation", description: "Create trigger-based automation rules that analyze, queue, and transcode automatically. One-click library optimization."),
                    FeatureItem(icon: "checkmark.seal", title: "Quality Assurance", description: "VMAF perceptual quality scoring validates every transcode. Visual A/B comparison lets you verify results."),
                    FeatureItem(icon: "chart.bar.xaxis", title: "Premium Analytics", description: "Library health reports, codec migration tracking, cost analytics, worker heatmaps, storage projections, and exportable PDF reports."),
                    FeatureItem(icon: "bell", title: "Notifications", description: "Get notified via email, Discord, Slack, Telegram, webhooks, or native macOS notifications."),
                ])),
                HelpSection(title: "First Steps", content: .steps([
                    HelpStep(number: 1, title: "Connect to Plex", description: "Sign in with your Plex account to discover your servers and libraries."),
                    HelpStep(number: 2, title: "Add a Worker", description: "Set up at least one transcode worker — your local machine works great to start."),
                    HelpStep(number: 3, title: "Run Analysis", description: "Let the Intelligence system analyze your library and generate recommendations with cost-benefit analysis."),
                    HelpStep(number: 4, title: "Start Transcoding", description: "Review recommendations, queue up transcode jobs, and let MediaFlow optimize your library."),
                    HelpStep(number: 5, title: "Set Up Automation", description: "Configure automation rules to keep your library optimized automatically as new content is added."),
                ])),
            ],
            searchKeywords: ["overview", "introduction", "start", "setup", "first", "begin", "what is", "getting started"]
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
                    "Once connected, MediaFlow fetches all movie and TV show libraries from your Plex server. The initial sync imports metadata, file paths, codec information, and viewing history (play counts, last watched dates) for every media item. Subsequent syncs are incremental and only fetch changes."
                )),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "Your Plex server must be running and reachable from this Mac for the connection to succeed.", style: .info),
                    HelpTip(icon: "arrow.clockwise", text: "If your libraries appear empty after connecting, try clicking the sync button on the Library page to trigger a fresh import.", style: .info),
                    HelpTip(icon: "lock.shield", text: "MediaFlow uses Plex's official OAuth flow — your password is never stored locally.", style: .success),
                    HelpTip(icon: "eye", text: "Viewing history (play counts and last watched dates) is synced automatically and used by the Intelligence system to make smarter recommendations.", style: .info),
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
                    HelpTip(icon: "cloud", text: "You can also deploy cloud GPU workers on-demand from the Servers page. See the Cloud GPU Workers topic for details.", style: .info),
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
                    "The Intelligence system scans your media library and evaluates each file's codec, resolution, bitrate, container format, and viewing patterns. It compares these against optimal targets and generates recommendations for files that would benefit from transcoding. Each recommendation includes estimated savings, transcode time, cloud cost estimate, and an ROI score. The system learns from your feedback and improves accuracy over time."
                )),
                HelpSection(title: "Start an Analysis", content: .steps([
                    HelpStep(number: 1, title: "Go to Intelligence", description: "Navigate to the Intelligence page (⌘6)."),
                    HelpStep(number: 2, title: "Choose Scope", description: "Analyze your entire collection, or use the library dropdown to analyze a specific library."),
                    HelpStep(number: 3, title: "Click Analyze", description: "Click the \"Analyze\" button. The system will scan all media items and generate prioritized recommendations."),
                    HelpStep(number: 4, title: "Review Recommendations", description: "Recommendations appear grouped by type and sorted by priority. Each shows estimated savings, ROI, and confidence level."),
                    HelpStep(number: 5, title: "Queue Transcodes", description: "Click \"Queue\" on individual recommendations, or use batch queuing to process multiple at once."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "clock", text: "The first analysis may take a minute for large libraries. Subsequent analyses are faster since only new or changed items are re-evaluated.", style: .info),
                    HelpTip(icon: "brain", text: "The system learns from your accept/dismiss decisions. Over time, recommendations become more personalized to your preferences.", style: .success),
                    HelpTip(icon: "hand.thumbsdown", text: "When you dismiss a recommendation, you can provide a reason (e.g., \"keep 4K\", \"keep original codec\"). This helps the system avoid similar suggestions in the future.", style: .info),
                    HelpTip(icon: "gearshape.arrow.triangle.2.circlepath", text: "Set up an automation rule to automatically queue top recommendations after each analysis. See the Automation Rules topic.", style: .info),
                ])),
            ],
            searchKeywords: ["analysis", "analyze", "intelligence", "recommendation", "scan", "first", "queue", "roi"]
        ),

        // MARK: Features

        HelpTopic(
            id: "library-management",
            category: .features,
            icon: "books.vertical",
            title: "Library Management",
            summary: "Browse, filter, inspect, and manage your media collection",
            sections: [
                HelpSection(title: "Overview", content: .text(
                    "The Library page (⌘1) is your central view of all media synced from Plex. It shows every movie and TV show episode with codec details, resolution, file size, play count, and transcode status. Click on any item to open a detailed inspection panel."
                )),
                HelpSection(title: "Features", content: .features([
                    FeatureItem(icon: "line.3.horizontal.decrease", title: "Filtering", description: "Filter by resolution (4K, 1080p, 720p, SD), codec (H.264, H.265, etc.), library, and transcode status using the filter pill bar."),
                    FeatureItem(icon: "arrow.up.arrow.down", title: "Sorting", description: "Sort by title, file size, resolution, codec, or date added. Click column headers to toggle sort direction."),
                    FeatureItem(icon: "magnifyingglass", title: "Search", description: "Use the search bar to find specific titles across all libraries. Also searchable via the Command Palette (⌘K)."),
                    FeatureItem(icon: "rectangle.stack", title: "Collections", description: "Build custom collections of media items for batch operations."),
                ])),
                HelpSection(title: "Media Item Detail", content: .text(
                    "Click on any media item to open the detail panel. This shows comprehensive information about the file including all audio tracks, subtitle tracks, full codec metadata, and file path. The detail panel also shows the item's complete transcode history (with status, codec changes, size reduction, and VMAF quality scores) and any active recommendations."
                )),
                HelpSection(title: "Detail Panel Sections", content: .features([
                    FeatureItem(icon: "doc.text", title: "File Metadata", description: "Resolution, codec, bitrate, container format, duration, file size, and full path."),
                    FeatureItem(icon: "speaker.wave.3", title: "Audio & Subtitle Tracks", description: "All audio tracks with codec and channel layout. All subtitle tracks with language."),
                    FeatureItem(icon: "clock.arrow.circlepath", title: "Transcode History", description: "Every past transcode job for this file — status, target codec, size reduction percentage, VMAF score, and date."),
                    FeatureItem(icon: "brain", title: "Recommendation Status", description: "Active recommendations for this file with type, priority, estimated savings, and current status (pending, queued, or dismissed)."),
                    FeatureItem(icon: "bolt.fill", title: "Quick Transcode", description: "Start a transcode directly from the detail panel without navigating away."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "Use the Command Palette (⌘K) to quickly search for a specific media item by name from anywhere in the app.", style: .info),
                    HelpTip(icon: "arrow.clockwise", text: "Use the sync button to refresh library data from Plex if items appear outdated.", style: .info),
                    HelpTip(icon: "eye", text: "Play count and last watched dates from Plex are synced and visible in the library. The Intelligence system uses this data for viewing-pattern-aware recommendations.", style: .info),
                ])),
            ],
            searchKeywords: ["library", "browse", "filter", "search", "sort", "collection", "media", "movies", "tv", "detail", "inspect", "metadata", "audio", "subtitle", "tracks"]
        ),

        HelpTopic(
            id: "transcoding",
            category: .features,
            icon: "gearshape.2",
            title: "Transcoding & Queue",
            summary: "Presets, queue strategies, drag-and-drop reordering, and monitoring",
            sections: [
                HelpSection(title: "How Transcoding Works", content: .text(
                    "MediaFlow transcodes media files using ffmpeg on your configured workers. Files are pulled from your Plex library (via NAS or local path), transcoded according to the selected preset, and the output replaces the original file. Plex automatically detects the updated file. After transcode, an optional VMAF quality check can validate perceptual quality."
                )),
                HelpSection(title: "Built-in Presets", content: .features([
                    FeatureItem(icon: "dial.medium", title: "Balanced", description: "H.265 with CRF 22. Good balance of quality and file size reduction."),
                    FeatureItem(icon: "internaldrive", title: "Storage Saver", description: "H.265 with CRF 26. Maximum space savings with acceptable quality loss."),
                    FeatureItem(icon: "iphone", title: "Mobile Optimized", description: "H.264 at 720p with CRF 23. Small files optimized for mobile streaming."),
                    FeatureItem(icon: "star", title: "Ultra Fidelity", description: "H.265 with CRF 18. Near-lossless quality for archival purposes."),
                ])),
                HelpSection(title: "Queue Management", content: .text(
                    "The Processing page (⌘3) shows all queued, active, completed, and failed transcode jobs. Active jobs display real-time progress with FPS, ETA, and percentage. You can pause, cancel, or re-queue jobs. Workers are assigned automatically based on availability and capability scoring."
                )),
                HelpSection(title: "Queue Priority Strategies", content: .features([
                    FeatureItem(icon: "list.number", title: "First In, First Out", description: "Default ordering — jobs are processed in the order they were queued."),
                    FeatureItem(icon: "internaldrive", title: "Biggest Savings First", description: "Prioritizes large files that yield the greatest storage savings."),
                    FeatureItem(icon: "bolt", title: "Fastest Jobs First", description: "Processes smaller files first for quick wins and rapid progress."),
                    FeatureItem(icon: "eye", title: "Most Watched First", description: "Prioritizes frequently-watched content so your most-viewed media gets optimized first."),
                ])),
                HelpSection(title: "Drag-and-Drop Reordering", content: .text(
                    "Queued jobs can be reordered by dragging and dropping. Each queued job shows a drag handle on the left and a position badge (#1, #2, etc.). Grab the handle and drag a job to a new position — the queue updates instantly and the new order is saved to the backend. Manual reordering takes precedence over the selected strategy."
                )),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "bolt.fill", text: "Workers with NVENC GPUs automatically use hardware encoding for dramatically faster transcodes.", style: .success),
                    HelpTip(icon: "exclamationmark.triangle", text: "If a GPU encode fails (driver issue), MediaFlow automatically retries with CPU encoding.", style: .warning),
                    HelpTip(icon: "arrow.up.arrow.down", text: "Change the queue strategy using the dropdown in the Processing page header. Your preference is saved and persists across sessions.", style: .info),
                    HelpTip(icon: "hand.draw", text: "Drag-and-drop only applies to queued jobs. Active, completed, and failed jobs are shown separately above the reorderable queue.", style: .info),
                ])),
            ],
            searchKeywords: ["transcode", "encode", "preset", "queue", "ffmpeg", "h265", "h264", "hevc", "processing", "progress", "drag", "drop", "reorder", "priority", "strategy", "fifo", "savings"]
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
                    HelpTip(icon: "keyboard", text: "You can also start a Quick Transcode from the Command Palette (⌘K) by searching for \"quick transcode\".", style: .info),
                ])),
            ],
            searchKeywords: ["quick", "manual", "local", "file", "drag", "drop", "outside", "plex"]
        ),

        HelpTopic(
            id: "intelligence",
            category: .features,
            icon: "brain",
            title: "Intelligence & Recommendations",
            summary: "AI analysis, cost-benefit scoring, viewing patterns, and learning",
            sections: [
                HelpSection(title: "How Intelligence Works", content: .text(
                    "The Intelligence system evaluates your media files against optimal encoding targets. It considers codec efficiency, bitrate relative to resolution, audio codec optimization, container format, viewing patterns, and historical transcode performance. Recommendations are prioritized by a composite score that factors in estimated savings, confidence level, and ROI."
                )),
                HelpSection(title: "Recommendation Types", content: .features([
                    FeatureItem(icon: "video", title: "Codec Upgrade", description: "Re-encode from less efficient codecs (e.g., H.264 to H.265 or AV1) for significant space savings."),
                    FeatureItem(icon: "speaker.wave.3", title: "Audio Optimization", description: "Convert lossless or inefficient audio codecs (e.g., PCM/DTS to AAC) to reduce file size."),
                    FeatureItem(icon: "doc", title: "Container Modernize", description: "Remux to a more compatible container (e.g., AVI to MKV) without re-encoding."),
                    FeatureItem(icon: "exclamationmark.triangle", title: "Quality Overkill", description: "Identifies files with excessively high bitrates relative to their resolution — where quality can be reduced without visible difference."),
                    FeatureItem(icon: "doc.on.doc", title: "Duplicate Detection", description: "Finds files that may be duplicates or very similar, suggesting consolidation."),
                    FeatureItem(icon: "arrow.down.circle", title: "Low Quality Upgrade", description: "Flags very low-quality files that might benefit from being replaced with better sources."),
                    FeatureItem(icon: "square.stack.3d.up", title: "Batch Similar", description: "Groups similar files for efficient batch processing with the same settings."),
                    FeatureItem(icon: "eye", title: "Viewing Pattern", description: "Recommendations based on how you actually watch content — aggressive compression for unwatched items, conservative settings for favorites."),
                ])),
                HelpSection(title: "Cost-Benefit Analysis", content: .text(
                    "Every recommendation includes a detailed cost-benefit breakdown. You'll see the estimated file size savings, transcode duration (based on historical FPS data for that codec pair), cloud GPU cost if using cloud workers, and an ROI score. For example, a recommendation might show \"Save 4.2 GB for $0.12 of GPU time (35x ROI)\" or \"Save 800 MB in ~3 hours of CPU time\". Recommendations can be sorted by ROI to find the most cost-effective optimizations."
                )),
                HelpSection(title: "Viewing-Pattern Intelligence", content: .text(
                    "MediaFlow pulls viewing history from Plex (play count and last watched date) and uses it to make smarter recommendations. Content you've never watched may be suggested for aggressive compression or archival encoding. Your most-watched content (10+ plays) gets the most conservative, quality-preserving recommendations. Items not watched in over two years are flagged as candidates for more aggressive space savings."
                )),
                HelpSection(title: "Preference Learning", content: .text(
                    "The Intelligence system learns from your feedback over time. When you dismiss a recommendation, you can provide a reason — such as \"don't touch 4K content\" or \"keep original codec\". The system tracks these preferences and automatically filters out similar recommendations in the future. It also calibrates savings estimates based on actual transcode results: if estimated savings were 2 GB but actual was 1.5 GB, future estimates for similar content are adjusted. The more you use MediaFlow, the smarter it gets."
                )),
                HelpSection(title: "Per-Library Analysis", content: .text(
                    "You can scope analysis to a single library using the library dropdown at the top of the Intelligence page. This generates a library-specific summary showing total potential savings, recommendation count, and top opportunities for just that library. Analysis history shows which libraries were analyzed with library badges on each run."
                )),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "slider.horizontal.3", text: "Adjust the minimum savings threshold in Settings to control which recommendations appear. Higher thresholds show only the most impactful items.", style: .info),
                    HelpTip(icon: "clock", text: "Enable auto-analyze in Settings to automatically scan for new recommendations when library changes are detected.", style: .success),
                    HelpTip(icon: "hand.thumbsdown", text: "Always provide a reason when dismissing — it dramatically improves future recommendation quality.", style: .info),
                    HelpTip(icon: "chart.bar", text: "The confidence indicator on each recommendation shows whether the estimate is based on learned data (high confidence) or default assumptions (lower confidence).", style: .info),
                ])),
            ],
            searchKeywords: ["intelligence", "recommendation", "analysis", "codec", "savings", "learned", "ratio", "priority", "batch", "auto", "roi", "cost", "benefit", "viewing", "pattern", "dismiss", "learning", "preference", "confidence"]
        ),

        HelpTopic(
            id: "analytics",
            category: .features,
            icon: "chart.bar.xaxis",
            title: "Analytics Dashboard",
            summary: "Health score, trends, premium visualizations, and PDF export",
            sections: [
                HelpSection(title: "Overview", content: .text(
                    "The Analytics Dashboard (⌘5) gives you a comprehensive view of your library's health, transcode history, and storage trends. It includes animated KPI counters, interactive charts, and detailed breakdowns. Numbers animate smoothly on page load for a polished experience."
                )),
                HelpSection(title: "Core Dashboard", content: .features([
                    FeatureItem(icon: "heart.text.square", title: "Library Health Score", description: "An overall score (0-100) based on codec efficiency, resolution distribution, and optimization coverage across your library. Displayed as an animated circular gauge."),
                    FeatureItem(icon: "chart.line.uptrend.xyaxis", title: "Storage Trends", description: "Charts showing total media size, total savings, and completed jobs over your selected time range (7, 30, 90, or 365 days) with animated sparklines."),
                    FeatureItem(icon: "chart.pie", title: "Codec & Resolution Distribution", description: "Visual breakdown of codec types and resolution tiers across your library."),
                    FeatureItem(icon: "clock.arrow.circlepath", title: "Transcode History", description: "Timeline of completed transcodes with speed, space saved, and worker used for each job."),
                    FeatureItem(icon: "binoculars", title: "Storage Predictions", description: "Animated forecast showing projected savings at 30 days, 90 days, and 1 year based on your current pace."),
                ])),
                HelpSection(title: "Premium Analytics Views", content: .features([
                    FeatureItem(icon: "cross.case", title: "Library Health Report", description: "Per-library health grades (A-F), optimization percentages, and codec breakdowns. Answers \"which library should I tackle first?\""),
                    FeatureItem(icon: "arrow.right.arrow.left", title: "Codec Migration Tracker", description: "Track your library-wide modernization progress with historical timeline charts. See how your codec mix has evolved over time."),
                    FeatureItem(icon: "dollarsign.circle", title: "Cost Analytics", description: "Cloud GPU spending trends, cost-per-GB-saved efficiency metrics, and cloud vs. local cost comparisons."),
                    FeatureItem(icon: "square.grid.3x3", title: "Worker Heatmap", description: "Grid visualization showing worker FPS performance by hour of day — identify peak performance windows and bottlenecks."),
                    FeatureItem(icon: "timeline.selection", title: "Job Timeline", description: "Visual timeline showing jobs across workers. See parallelization, idle gaps, and identify bottlenecks at a glance."),
                    FeatureItem(icon: "chart.line.uptrend.xyaxis", title: "Storage Projection", description: "12-month savings forecast with confidence bands (optimistic to conservative) and monthly pace tracking."),
                    FeatureItem(icon: "target", title: "Codec Strategy Advisor", description: "AI-recommended codec targets per library with per-resolution breakdowns and projected savings."),
                    FeatureItem(icon: "checkmark.seal", title: "VMAF Dashboard", description: "Aggregate quality validation scores across all completed transcodes, broken down by codec pair."),
                ])),
                HelpSection(title: "PDF Export", content: .text(
                    "Export a detailed health report as a PDF using the \"Export PDF\" button in the dashboard header. The report includes your health score, storage trends, codec distribution, and key metrics — suitable for sharing or archival."
                )),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "Use the time range selector in the dashboard header to switch between 7-day, 30-day, 90-day, and 1-year views. Charts and trends update automatically.", style: .info),
                    HelpTip(icon: "chart.bar", text: "The health score updates after each transcode completes and after library syncs.", style: .info),
                    HelpTip(icon: "keyboard", text: "Jump to Analytics from anywhere using ⌘5 or search \"analytics\" in the Command Palette (⌘K).", style: .info),
                ])),
            ],
            searchKeywords: ["analytics", "dashboard", "health", "score", "chart", "storage", "trend", "prediction", "pdf", "export", "report", "heatmap", "timeline", "migration", "projection", "vmaf", "cost", "kpi"]
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
                    HelpTip(icon: "gearshape.arrow.triangle.2.circlepath", text: "Combine scheduling with automation rules for powerful workflows — e.g., auto-queue recommendations during off-peak hours only.", style: .info),
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
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "gearshape.arrow.triangle.2.circlepath", text: "Automation rules can trigger notifications as an action — e.g., \"When a job fails, send a Discord notification.\"", style: .info),
                    HelpTip(icon: "info.circle", text: "Real-time notifications also appear as toast banners at the top of the app window via WebSocket.", style: .info),
                ])),
            ],
            searchKeywords: ["notification", "email", "webhook", "discord", "slack", "telegram", "alert", "notify", "smtp"]
        ),

        HelpTopic(
            id: "automation",
            category: .features,
            icon: "gearshape.arrow.triangle.2.circlepath",
            title: "Automation Rules",
            summary: "Create trigger-based workflows that run automatically",
            sections: [
                HelpSection(title: "Overview", content: .text(
                    "The Automation page lets you create rules that fire automatically when events occur. Each rule consists of a trigger (what starts it), optional conditions (what must be true), and an action (what to do). This enables \"set it and forget it\" workflows that keep your library optimized without manual intervention."
                )),
                HelpSection(title: "Triggers", content: .features([
                    FeatureItem(icon: "brain", title: "Analysis Complete", description: "Fires when a recommendation analysis finishes — useful for auto-queuing top recommendations."),
                    FeatureItem(icon: "checkmark.circle", title: "Job Complete", description: "Fires when a transcode job completes successfully — useful for triggering follow-up actions."),
                    FeatureItem(icon: "xmark.circle", title: "Job Failed", description: "Fires when a transcode job fails — useful for sending alerts or pausing the queue."),
                    FeatureItem(icon: "arrow.clockwise", title: "Library Sync", description: "Fires when a library sync finishes — useful for auto-analyzing new content."),
                    FeatureItem(icon: "internaldrive", title: "Storage Threshold", description: "Fires when free storage drops below a configured threshold."),
                    FeatureItem(icon: "calendar", title: "Schedule", description: "Fires on a cron-like schedule — useful for periodic maintenance tasks."),
                ])),
                HelpSection(title: "Conditions", content: .text(
                    "Conditions add filters to your triggers. For example, you might want an \"Analysis Complete\" rule to only fire when total potential savings exceed 50 GB, or a \"Job Failed\" rule to only fire for high-priority jobs. Conditions support comparisons like greater than, less than, equals, contains, and more."
                )),
                HelpSection(title: "Actions", content: .features([
                    FeatureItem(icon: "plus.circle", title: "Queue Recommendations", description: "Automatically queue the top N recommendations — great for continuous optimization."),
                    FeatureItem(icon: "magnifyingglass", title: "Run Analysis", description: "Trigger a fresh recommendation analysis on your library."),
                    FeatureItem(icon: "bell", title: "Send Notification", description: "Send an alert via your configured notification channels."),
                    FeatureItem(icon: "pause.circle", title: "Pause Queue", description: "Stop all queue processing — useful as a safety valve when errors occur."),
                    FeatureItem(icon: "cloud", title: "Deploy Cloud GPU", description: "Automatically provision a cloud GPU worker when there's work to do."),
                ])),
                HelpSection(title: "Example Rules", content: .tips([
                    HelpTip(icon: "lightbulb", text: "\"When analysis completes and savings > 50 GB, auto-queue top 20 recommendations with Balanced preset\" — keeps your library optimized with zero manual effort.", style: .success),
                    HelpTip(icon: "lightbulb", text: "\"When a job fails, send a Discord notification\" — stay informed about issues without checking the app.", style: .success),
                    HelpTip(icon: "lightbulb", text: "\"When library syncs, run analysis\" — automatically scan for optimization opportunities whenever new content is added.", style: .success),
                ])),
                HelpSection(title: "Managing Rules", content: .steps([
                    HelpStep(number: 1, title: "Create a Rule", description: "Navigate to the Automation page and click \"Create Rule\". Give it a name, select a trigger, add conditions, and choose an action."),
                    HelpStep(number: 2, title: "Enable/Disable", description: "Use the toggle switch on each rule to enable or disable it without deleting."),
                    HelpStep(number: 3, title: "Monitor Activity", description: "Each rule shows how many times it has fired and when it last triggered."),
                    HelpStep(number: 4, title: "Edit or Delete", description: "Click a rule to edit its configuration, or use the delete button to remove it."),
                ])),
            ],
            searchKeywords: ["automation", "rule", "trigger", "action", "condition", "workflow", "auto", "queue", "schedule", "event", "set and forget"]
        ),

        HelpTopic(
            id: "one-click-optimize",
            category: .features,
            icon: "wand.and.stars",
            title: "One-Click Optimize",
            summary: "Optimize an entire library with a single click",
            sections: [
                HelpSection(title: "Overview", content: .text(
                    "One-Click Optimize chains together multiple steps into a single workflow: sync your library, run analysis, queue all high-confidence recommendations, transcode, and replace originals. It's the fastest way to optimize an entire library or get a new library into shape."
                )),
                HelpSection(title: "How It Works", content: .steps([
                    HelpStep(number: 1, title: "Sync Library", description: "Fetches the latest metadata from Plex to ensure all items are up to date."),
                    HelpStep(number: 2, title: "Run Analysis", description: "The Intelligence system scans all items and generates recommendations."),
                    HelpStep(number: 3, title: "Queue Recommendations", description: "High-confidence recommendations are automatically queued with the selected preset."),
                    HelpStep(number: 4, title: "Transcode", description: "Queued jobs are processed by available workers. Progress is shown in real-time."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "You can monitor progress on the Processing page (⌘3) while optimization is running.", style: .info),
                    HelpTip(icon: "exclamationmark.triangle", text: "One-Click Optimize processes all high-confidence recommendations. Review the Intelligence page first if you want to be selective about what gets transcoded.", style: .warning),
                    HelpTip(icon: "gearshape.arrow.triangle.2.circlepath", text: "For ongoing optimization, consider setting up automation rules instead — they run automatically whenever new content is added.", style: .info),
                ])),
            ],
            searchKeywords: ["optimize", "one click", "auto", "library", "wizard", "batch", "all", "full"]
        ),

        HelpTopic(
            id: "command-palette",
            category: .features,
            icon: "command",
            title: "Command Palette",
            summary: "Quick navigation, media search, and actions from anywhere",
            sections: [
                HelpSection(title: "Overview", content: .text(
                    "The Command Palette (⌘K) gives you instant access to navigation, actions, and media search from anywhere in the app. Start typing to filter commands or search your media library. It also remembers your recent actions for quick replay."
                )),
                HelpSection(title: "What You Can Do", content: .features([
                    FeatureItem(icon: "arrow.right", title: "Navigate", description: "Jump to any page — Library, Processing, Analytics, Intelligence, Settings, and more."),
                    FeatureItem(icon: "magnifyingglass", title: "Search Media", description: "Type 2+ characters to search your media library by title. Results show the year, codec, and file size. Click to navigate to that item."),
                    FeatureItem(icon: "bolt", title: "Quick Actions", description: "Run common actions like \"Sync Libraries\", \"Run Analysis\", \"Export PDF Report\", or \"Open Quick Transcode\"."),
                    FeatureItem(icon: "books.vertical", title: "Library-Scoped Actions", description: "Type \"analyze\" or \"recommend\" to see per-library quick actions — e.g., \"Run Analysis for Movies\" or \"Show Recommendations for TV Shows\"."),
                    FeatureItem(icon: "clock", title: "Recent Actions", description: "When the search field is empty, your most recent palette actions are shown for quick replay."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "keyboard", text: "Press ⌘K from anywhere to open the palette. Press Escape or click outside to dismiss.", style: .info),
                    HelpTip(icon: "magnifyingglass", text: "Media search uses a debounced API call — type naturally and results appear after a brief pause. Up to 8 results are shown.", style: .info),
                    HelpTip(icon: "clock", text: "The palette remembers your last 10 actions. When you open the palette with an empty search, recent actions appear at the top for quick access.", style: .info),
                    HelpTip(icon: "return", text: "Press Enter to execute the first matching command or navigate to the first media result.", style: .info),
                ])),
            ],
            searchKeywords: ["command", "palette", "search", "navigate", "quick", "action", "cmd k", "recent", "media search", "find"]
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
                    HelpStep(number: 3, title: "Wait for Provisioning", description: "MediaFlow creates the instance, installs dependencies, and registers it as a worker. Progress is shown in real-time via WebSocket updates."),
                    HelpStep(number: 4, title: "Start Transcoding", description: "The cloud worker is now available for job assignment alongside your local workers."),
                ])),
                HelpSection(title: "Cost Management", content: .features([
                    FeatureItem(icon: "dollarsign.circle", title: "Cost Tracking", description: "Per-instance and per-job costs are tracked and displayed on the Cost Analytics dashboard."),
                    FeatureItem(icon: "clock.badge.xmark", title: "Idle Timeout", description: "Cloud workers are automatically destroyed after a configurable idle period (default: 15 minutes)."),
                    FeatureItem(icon: "exclamationmark.shield", title: "Spend Cap", description: "Set a maximum monthly spend to prevent runaway costs. Workers are stopped when the cap is reached."),
                    FeatureItem(icon: "chart.bar", title: "ROI Tracking", description: "The Cost Analytics dashboard shows cost-per-GB-saved and compares cloud vs. local costs so you can evaluate if cloud is worth it."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "exclamationmark.triangle", text: "Never manually update NVIDIA drivers on Vultr GPU instances. The vGPU guest driver must match the hypervisor version — changing it will permanently break GPU access.", style: .warning),
                    HelpTip(icon: "info.circle", text: "Cloud workers use Jellyfin ffmpeg for maximum NVENC compatibility with Vultr's driver version.", style: .info),
                    HelpTip(icon: "gearshape.arrow.triangle.2.circlepath", text: "Create an automation rule with a \"Deploy Cloud GPU\" action to automatically provision cloud workers when there are queued jobs.", style: .info),
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
                    FeatureItem(icon: "bolt.fill", title: "NVENC Auto-Upgrade", description: "When a worker has NVENC GPU support, CPU codecs are automatically upgraded to GPU equivalents (e.g., libx265 to hevc_nvenc)."),
                    FeatureItem(icon: "arrow.down.to.line", title: "NVENC Fallback", description: "If GPU encoding fails (driver issue), the job automatically retries with CPU encoding."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "Worker health checks run automatically. Unhealthy workers are excluded from job assignment until they recover.", style: .info),
                    HelpTip(icon: "server.rack", text: "You can view detailed worker stats and comparison on the Servers page (⌘4).", style: .info),
                    HelpTip(icon: "square.grid.3x3", text: "Use the Worker Heatmap in Analytics (⌘5) to identify which workers perform best at different times of day.", style: .info),
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
                    FeatureItem(icon: "arrow.up.left.and.arrow.down.right", title: "Resolution", description: "Optionally downscale to a target resolution (e.g., 4K to 1080p)."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "CRF values: lower = higher quality, larger files. Typical range: 18 (high quality) to 28 (small files). 22-23 is a good default.", style: .info),
                    HelpTip(icon: "exclamationmark.triangle", text: "NVENC GPUs don't support CRF directly. MediaFlow automatically converts to equivalent VBR settings when a GPU worker is used.", style: .warning),
                    HelpTip(icon: "target", text: "Use the Codec Strategy Advisor in Analytics to see which codecs work best for each of your libraries before creating custom presets.", style: .info),
                ])),
            ],
            searchKeywords: ["preset", "custom", "create", "codec", "crf", "bitrate", "resolution", "quality", "settings", "h264", "h265", "av1"]
        ),

        HelpTopic(
            id: "vmaf-quality",
            category: .advanced,
            icon: "checkmark.seal",
            title: "VMAF Quality Assurance",
            summary: "Perceptual quality scoring, A/B comparison, and validation",
            sections: [
                HelpSection(title: "What is VMAF?", content: .text(
                    "VMAF (Video Multimethod Assessment Fusion) is Netflix's perceptual video quality metric. It produces a score from 0 to 100 that closely correlates with human perception of quality. A score of 95+ is excellent (nearly indistinguishable from the original), 90-95 is very good, 80-90 is good, and below 80 may show visible quality loss. MediaFlow can automatically run VMAF scoring after each transcode to validate quality."
                )),
                HelpSection(title: "How It Works", content: .steps([
                    HelpStep(number: 1, title: "Transcode Completes", description: "After a transcode job finishes, MediaFlow can automatically compute the VMAF score by comparing the original and transcoded files."),
                    HelpStep(number: 2, title: "Quality Score", description: "The VMAF score is stored with the job and displayed as a quality badge (e.g., \"98.2 VMAF — Excellent\") on the job card and in the media detail panel."),
                    HelpStep(number: 3, title: "Quality Tracking", description: "VMAF scores are aggregated across all jobs and available in the VMAF Dashboard in Analytics."),
                ])),
                HelpSection(title: "VMAF Dashboard", content: .features([
                    FeatureItem(icon: "gauge.with.dots.needle.67percent", title: "Average Quality Score", description: "Your overall average VMAF score across all scored transcodes, with color-coded confidence level."),
                    FeatureItem(icon: "chart.bar", title: "Per-Codec-Pair Breakdown", description: "See quality scores by source-to-target codec pair (e.g., H.264 to HEVC averages 96.3 VMAF). Identify which conversions retain the most quality."),
                    FeatureItem(icon: "number", title: "Score Distribution", description: "Total scored jobs, minimum score, and maximum score across your transcode history."),
                ])),
                HelpSection(title: "Visual A/B Comparison", content: .text(
                    "For completed transcodes, you can open a visual A/B comparison that shows side-by-side frame captures from the original and transcoded files. Each pair is taken at the same timestamp so you can directly compare quality. The comparison view also shows metadata for both versions — codec, resolution, file size, bitrate, and VMAF score — making it easy to verify that quality was preserved."
                )),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "VMAF scoring requires ffmpeg with the libvmaf filter. Most ffmpeg builds include it by default.", style: .info),
                    HelpTip(icon: "exclamationmark.triangle", text: "VMAF computation is CPU-intensive and adds time after the transcode. For large files, it can take several minutes.", style: .warning),
                    HelpTip(icon: "checkmark.seal", text: "A VMAF score above 93 is generally considered transparent — most viewers cannot distinguish it from the original.", style: .success),
                    HelpTip(icon: "chart.bar", text: "Check the VMAF Dashboard in Analytics regularly. If a preset consistently produces scores below 90, consider using a lower CRF value.", style: .info),
                ])),
            ],
            searchKeywords: ["vmaf", "quality", "score", "perceptual", "comparison", "a/b", "before", "after", "validation", "visual", "thumbnail", "side by side"]
        ),

        HelpTopic(
            id: "codec-strategy",
            category: .advanced,
            icon: "arrow.right.arrow.left",
            title: "Codec Strategy & Migration",
            summary: "AI-recommended codec targets and library modernization tracking",
            sections: [
                HelpSection(title: "Codec Strategy Advisor", content: .text(
                    "The Codec Strategy Advisor analyzes your completed transcode history and recommends the optimal codec target for each library. It considers actual compression ratios, quality scores, and transcode speeds from your real data — not generic benchmarks. For example, it might suggest \"Your Movies library saves 58% with HEVC but your TV library only saves 42% — consider AV1 for TV.\""
                )),
                HelpSection(title: "Strategy Features", content: .features([
                    FeatureItem(icon: "books.vertical", title: "Per-Library Targets", description: "Each library gets its own codec recommendation based on its content characteristics."),
                    FeatureItem(icon: "4k.tv", title: "Per-Resolution Advice", description: "Recommendations are further broken down by resolution — 4K content may benefit more from AV1 than 1080p content does."),
                    FeatureItem(icon: "chart.bar", title: "Projected Savings", description: "See the total projected savings if you follow the recommended strategy for each library."),
                    FeatureItem(icon: "number", title: "Based on Real Data", description: "Recommendations are derived from your actual transcode history — average compression ratios, VMAF scores, and FPS by codec pair."),
                ])),
                HelpSection(title: "Codec Migration Tracker", content: .text(
                    "The Codec Migration Tracker shows your library-wide progress toward modern codecs. It displays a color-coded stacked bar showing the current codec composition (e.g., 67% HEVC, 23% H.264, 10% other) alongside a historical timeline chart showing how that mix has changed over time. This is a great way to visualize the impact of your optimization work and track progress toward a target."
                )),
                HelpSection(title: "Migration Features", content: .features([
                    FeatureItem(icon: "gauge.with.dots.needle.67percent", title: "Modern Codec Percentage", description: "A single number showing what percentage of your library uses modern codecs (HEVC + AV1)."),
                    FeatureItem(icon: "chart.line.uptrend.xyaxis", title: "Historical Timeline", description: "Chart tracking your codec composition over weeks and months — see how your library has evolved."),
                    FeatureItem(icon: "paintpalette", title: "Color-Coded Distribution", description: "HEVC shown in green, AV1 in blue, H.264 in orange, and legacy codecs in red for quick visual assessment."),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "target", text: "Use the Codec Strategy Advisor's recommendations when creating custom presets — it tells you exactly which codec to target for each library and resolution tier.", style: .success),
                    HelpTip(icon: "chart.bar", text: "The Migration Tracker updates automatically after each transcode completes. Check it weekly to see your progress.", style: .info),
                    HelpTip(icon: "brain", text: "Strategy recommendations improve over time as more transcodes complete and provide additional data points.", style: .info),
                ])),
            ],
            searchKeywords: ["codec", "strategy", "migration", "tracker", "hevc", "av1", "h264", "modernize", "target", "per library", "progress", "recommendation"]
        ),

        HelpTopic(
            id: "cost-analytics",
            category: .advanced,
            icon: "dollarsign.circle",
            title: "Cost & ROI Analytics",
            summary: "Cloud spending, cost efficiency, and cloud vs. local comparison",
            sections: [
                HelpSection(title: "Overview", content: .text(
                    "The Cost Analytics dashboard helps you understand the true cost of your transcoding operations. It tracks cloud GPU spending per job and per instance, calculates efficiency metrics, and compares cloud costs against estimated local processing costs — helping you make informed decisions about your infrastructure."
                )),
                HelpSection(title: "Key Metrics", content: .features([
                    FeatureItem(icon: "dollarsign.circle", title: "Total Cloud Cost", description: "Cumulative cloud GPU spending across all jobs and instances."),
                    FeatureItem(icon: "scalemass", title: "Cost per GB Saved", description: "Efficiency metric showing how much you spend per gigabyte of storage reclaimed — lower is better."),
                    FeatureItem(icon: "arrow.left.arrow.right", title: "Cloud vs. Local", description: "Side-by-side comparison of cloud GPU costs vs. estimated local CPU costs for the same work."),
                    FeatureItem(icon: "chart.line.uptrend.xyaxis", title: "Monthly Projection", description: "Projected monthly cloud spend based on your current usage patterns."),
                ])),
                HelpSection(title: "Cost Tracking", content: .text(
                    "Every cloud GPU job automatically records its cost based on instance runtime and pricing tier. Per-instance costs (idle time between jobs) are also tracked separately. Monthly spending charts show trends over time, and the cloud vs. local comparison helps you decide if cloud GPU is cost-effective for your workload."
                )),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "exclamationmark.shield", text: "Set a monthly spend cap in Settings under Cloud GPU to prevent unexpected charges. MediaFlow will automatically stop cloud workers when the cap is reached.", style: .warning),
                    HelpTip(icon: "clock.badge.xmark", text: "Keep the idle timeout low (5-15 minutes) to minimize costs from idle cloud instances between jobs.", style: .info),
                    HelpTip(icon: "chart.bar", text: "Check the Cost per GB Saved metric regularly. If it's rising, you may be transcoding files with diminishing returns.", style: .info),
                    HelpTip(icon: "internaldrive", text: "Use the \"Biggest Savings First\" queue strategy when running cloud workers to maximize the value of each GPU-hour.", style: .success),
                ])),
            ],
            searchKeywords: ["cost", "roi", "analytics", "cloud", "spending", "expense", "efficiency", "per gb", "local", "comparison", "budget", "spend cap"]
        ),

        // MARK: Reference

        HelpTopic(
            id: "keyboard-shortcuts",
            category: .reference,
            icon: "keyboard",
            title: "Keyboard Shortcuts",
            summary: "Complete list of keyboard shortcuts and the Command Palette",
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
                HelpSection(title: "Command Palette", content: .shortcuts([
                    HelpShortcut(keys: "⌘K", description: "Open Command Palette — search media, navigate, or run quick actions"),
                    HelpShortcut(keys: "Esc", description: "Close Command Palette or dismiss dialogs"),
                    HelpShortcut(keys: "↑ ↓", description: "Navigate through palette results"),
                    HelpShortcut(keys: "Return", description: "Execute selected command or navigate to selected media item"),
                ])),
                HelpSection(title: "Tips", content: .tips([
                    HelpTip(icon: "info.circle", text: "All navigation shortcuts use ⌘ (Command) plus a number key. The number corresponds to the item's position in the sidebar.", style: .info),
                    HelpTip(icon: "command", text: "The Command Palette (⌘K) is the fastest way to navigate — type a few characters and press Enter to jump to any page, search media, or trigger actions.", style: .success),
                ])),
            ],
            searchKeywords: ["keyboard", "shortcut", "hotkey", "command", "cmd", "keybinding", "shortcut", "palette"]
        ),

        HelpTopic(
            id: "troubleshooting",
            category: .reference,
            icon: "wrench.and.screwdriver",
            title: "Troubleshooting",
            summary: "Common issues and their solutions",
            sections: [
                HelpSection(title: "Connection & Setup", content: .troubleshoot([
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
                        problem: "SSH worker connection fails",
                        cause: "SSH key authentication failed, the remote host is unreachable, or the SSH port is blocked.",
                        solution: "Verify you can SSH to the worker manually: ssh -i /path/to/key user@host. Check that the SSH key path, username, and port in MediaFlow match your SSH config."
                    ),
                    TroubleshootItem(
                        problem: "Notifications aren't being delivered",
                        cause: "The notification channel is misconfigured, or credentials are invalid.",
                        solution: "Go to Settings (⌘7) and use the \"Send Test\" button for each configured channel. Check SMTP credentials, webhook URLs, or bot tokens for typos."
                    ),
                ])),
                HelpSection(title: "Transcoding Issues", content: .troubleshoot([
                    TroubleshootItem(
                        problem: "Transcode jobs stuck in \"Queued\" status",
                        cause: "No workers are available, all workers are busy, or scheduling rules are blocking execution.",
                        solution: "Check the Servers page (⌘4) to verify at least one worker is online and healthy. Check Settings (⌘7) to ensure current time is within active hours. If using cloud workers, verify the worker hasn't been torn down due to idle timeout."
                    ),
                    TroubleshootItem(
                        problem: "NVENC encoding fails on cloud worker",
                        cause: "The NVENC SDK version bundled with the static ffmpeg build may be incompatible with the Vultr vGPU driver.",
                        solution: "MediaFlow automatically falls back to CPU encoding. If persistent, the provisioning system will install Jellyfin ffmpeg (compatible with older NVENC SDK). Check worker logs for details."
                    ),
                    TroubleshootItem(
                        problem: "Transcoded file is larger than the original",
                        cause: "The source file was already well-optimized, or the CRF value is too low (high quality) for the content type.",
                        solution: "Try a higher CRF value (e.g., 24-26) or use the Storage Saver preset. Some already-efficient files may not benefit from re-encoding. The Intelligence system's confidence score helps identify these cases."
                    ),
                    TroubleshootItem(
                        problem: "Drag-and-drop queue reordering isn't working",
                        cause: "Only jobs with \"queued\" status can be reordered. Active, completed, and failed jobs cannot be dragged.",
                        solution: "Ensure the job is in \"queued\" status. Look for the drag handle icon on the left side of queued job cards in the Processing page."
                    ),
                ])),
                HelpSection(title: "Intelligence & Analysis", content: .troubleshoot([
                    TroubleshootItem(
                        problem: "Analysis shows no recommendations",
                        cause: "Your library is already well-optimized, or the minimum savings threshold is set too high.",
                        solution: "Lower the minimum savings threshold in Settings (⌘7) under Intelligence. Even optimized libraries may have opportunities with a lower threshold."
                    ),
                    TroubleshootItem(
                        problem: "Recommendations keep suggesting items I've dismissed",
                        cause: "Dismissals without reasons don't create strong preference signals for the learning system.",
                        solution: "When dismissing, always provide a reason (e.g., \"keep 4K\", \"keep original codec\"). This teaches the system your preferences. After several dismissals with reasons, similar recommendations will be automatically filtered."
                    ),
                    TroubleshootItem(
                        problem: "VMAF scores seem unexpectedly low",
                        cause: "The transcode settings may be too aggressive for the content type, or the content has characteristics that are hard to compress (grain, fast motion).",
                        solution: "Check which preset was used and consider lowering the CRF value. The VMAF Dashboard in Analytics shows scores by codec pair — look for patterns. Content with heavy grain or fast motion typically needs lower CRF values to maintain quality."
                    ),
                ])),
                HelpSection(title: "Automation & Performance", content: .troubleshoot([
                    TroubleshootItem(
                        problem: "Automation rules aren't firing",
                        cause: "The rule may be disabled, the trigger event isn't occurring, or conditions aren't being met.",
                        solution: "Check the Automation page to verify the rule is enabled (toggle is on). Review the trigger type and conditions. Check the \"trigger count\" — if it's 0, the event hasn't occurred. Try simplifying conditions to test."
                    ),
                    TroubleshootItem(
                        problem: "Cloud GPU costs are higher than expected",
                        cause: "Cloud instances may be staying alive too long between jobs, or the spend cap isn't configured.",
                        solution: "Reduce the idle timeout in Settings (default 15 minutes, try 5 minutes). Set a monthly spend cap to prevent runaway costs. Check the Cost Analytics dashboard for spending trends and idle time metrics."
                    ),
                    TroubleshootItem(
                        problem: "Analytics data appears stale or incomplete",
                        cause: "Analytics are computed from completed job data. New jobs or recently synced libraries may not yet be reflected.",
                        solution: "Wait for in-progress jobs to complete, then refresh the Analytics page. Some premium analytics (VMAF, heatmap, timeline) require sufficient historical data — they populate over time as more jobs complete."
                    ),
                ])),
            ],
            searchKeywords: ["troubleshoot", "problem", "issue", "error", "fix", "help", "debug", "not working", "stuck", "fail", "offline", "vmaf", "automation", "cost", "drag", "drop", "recommendation", "dismiss"]
        ),
    ]
}
