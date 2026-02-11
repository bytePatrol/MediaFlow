# Plex Media Optimizer - Comprehensive Project Specification

## Project Overview

Build a professional-grade macOS application that provides intelligent media library analysis and distributed transcoding for Plex servers. This application combines sophisticated data visualization, powerful filtering capabilities, and enterprise-level transcoding orchestration into a polished, native experience.

## Core Philosophy

This is a **production-quality tool** designed for power users managing large media libraries. Every feature should be implemented with attention to:
- **Performance**: Handle libraries with 10,000+ items smoothly
- **Reliability**: Graceful error handling, resume capability, data integrity
- **Polish**: Professional UI/UX with attention to detail throughout
- **Intelligence**: Provide actionable insights, not just raw data

## Technical Foundation

### Primary Technologies
- **Language**: Swift (native macOS app using SwiftUI)
- **Backend**: Python FastAPI service for Plex integration and transcode orchestration
- **Database**: SQLite for local caching and job queue management
- **FFmpeg**: Core transcoding engine with hardware acceleration support

### Architecture
- Native macOS frontend communicating with local Python backend via REST API
- Background service architecture for long-running transcode operations
- Distributed worker model supporting multiple transcode servers
- Event-driven progress updates using WebSockets for real-time monitoring

## Feature Set: Complete Implementation

### 1. Media Library Analysis & Visualization

**Core Data Display**
- Connect to Plex server via API (support for multiple Plex servers)
- Retrieve and cache all media across all libraries (Movies, TV Shows, Music, etc.)
- Display comprehensive technical details for each media file:
  - Resolution (4K, 1080p, 720p, SD) with HDR/SDR indicator
  - Video codec (H.264, H.265/HEVC, AV1, VP9, etc.)
  - Bitrate (video + audio breakdown)
  - File size with human-readable formatting
  - Audio codec and quality (Dolby Atmos, TrueHD, DTS-HD MA, AAC, etc.)
  - Audio channel configuration (7.1, 5.1, stereo)
  - Container format (MKV, MP4, AVI, etc.)
  - Frame rate (24fps, 30fps, 60fps)
  - Duration
  - File path and last modified date

**Advanced Filtering & Sorting**
- Multi-column sortable data table with persistent sort preferences
- Real-time search across all metadata fields
- Advanced filter builder with compound logic:
  - File size ranges (e.g., "30GB - 50GB" or ">30GB")
  - Resolution tiers (4K, 1080p, 720p, SD)
  - Audio codec matching (Atmos, DTS-X, TrueHD, etc.)
  - Video codec filtering
  - Bitrate ranges
  - Library type (Movies, TV Shows, etc.)
  - HDR/SDR distinction
  - Date ranges (added to Plex, file modification)
- Save and load custom filter presets
- "Quick Filters" for common searches (high-quality presets)
- Bulk selection tools (select all filtered, select by criteria, select series/season)

**Data Export**
- Export filtered results to CSV, JSON, or Excel format
- Include all visible columns or customize export fields
- Export summary statistics and charts
- Generate shareable reports with visual breakdowns

**Design Inspiration**: Reference the sample_designs folder for modern, responsive layout patterns. The UI should feature:
- Clean, information-dense tables with subtle hover states
- Sophisticated color-coding for quality tiers (green for optimal, yellow for medium, red for inefficient)
- Card-based layout options as alternative to table view
- Smooth transitions and micro-interactions
- Dark mode support with carefully chosen accent colors

### 2. Intelligence & Recommendations Engine

**Smart Storage Recommendations**
- Analyze entire library and generate prioritized recommendations:
  - **Quality Overkill Detection**: Flag 4K HDR content that's rarely watched (< 2 views in past year) and recommend downscaling
  - **Watch Frequency Analysis**: Correlate file size with play count to identify candidates for optimization
  - **Redundant Quality Levels**: Detect when multiple versions exist and suggest consolidation strategy
  - **Codec Modernization**: Identify H.264 files that would benefit from H.265 conversion
- Present recommendations in dashboard with estimated storage savings
- One-click batch queue all recommendations

**Duplicate Detection**
- Scan across all libraries for duplicate content:
  - Same movie/episode in different qualities
  - Same content in different formats (MKV vs MP4)
  - Partial duplicates (different cuts, editions)
- Display duplicates grouped with quality comparison
- Recommend which version to keep based on quality, format, and file size efficiency
- Bulk deletion with safety confirmations

**Quality Gap Analysis**
- Calculate library-wide quality statistics:
  - Average bitrate by resolution tier
  - Codec distribution pie charts
  - Resolution distribution
  - Audio quality breakdown
- Highlight outliers:
  - Content significantly below library average
  - SD content in predominantly HD library
  - Low-bitrate encodes that should be upgraded
- Generate "upgrade targets" list with prioritization

**Codec Compatibility Matrix**
- Detect Plex clients/devices from server API
- Build compatibility matrix showing:
  - Which devices can direct play each codec
  - Expected transcode scenarios
  - Recommended optimization targets for your ecosystem
- Suggest library-wide optimizations (e.g., "Convert to H.265 for Roku compatibility")

### 3. Transcoding Engine

**Core Transcoding Interface**
- Select single file, multiple files, entire seasons, or entire series
- Present encoding options in clean, visual interface with previews:
  - **Target Resolution**: 4K, 1080p, 720p, 480p (with aspect ratio preservation)
  - **Video Codec**: H.264, H.265/HEVC, AV1 (with hardware acceleration auto-detection)
  - **Bitrate Control**: CRF (quality-based) or CBR/VBR with Mbps selector
  - **Audio Handling**: 
    - Copy/passthrough (maintain original)
    - Transcode to AAC, AC3, or downmix options
    - Preserve multi-audio tracks or select specific tracks
  - **Subtitle Options**: Copy all, select specific tracks, or embed/remove
  - **Container Format**: MKV, MP4, or maintain original
  - **HDR Handling**: Preserve HDR10/Dolby Vision or tone-map to SDR

**Preset Profiles System**
- Create and save custom encoding profiles with descriptive names:
  - "Mobile Optimized" (720p H.265, AAC stereo, ~2Mbps)
  - "4K to 1080p Atmos Preserve" (1080p H.265, passthrough audio, CRF 20)
  - "Archive Quality" (maintain resolution, H.265 high bitrate)
  - "Compatibility Mode" (1080p H.264, AAC 5.1, MP4 container)
- Share profiles as JSON for community sharing
- Import preset profiles from others
- Profile templates for common devices (Apple TV, Roku, Fire Stick, etc.)

**Advanced Encoding Options**
- **Two-Pass Encoding**: Enable for highest quality at target file size
- **Hardware Acceleration**: 
  - Automatic detection of NVENC, QuickSync, VideoToolbox, AMD VCE
  - Manual override for specific encoder selection
  - CPU fallback for unsupported codecs
- **Quality Comparison Preview**: 
  - Generate 30-60 second sample from middle of video
  - Side-by-side comparison player (original vs encoded)
  - Show file size projection based on sample
  - Approve or adjust settings before full encode
- **Encoding Parameters**: Advanced users can set:
  - Custom FFmpeg flags
  - Encoder-specific tuning (film, animation, grain)
  - Deinterlacing and frame rate conversion
  - Resolution scaling algorithms (bicubic, lanczos)

**Batch Processing & Queue Management**
- Visual queue interface showing all pending jobs
- Drag-and-drop reordering of queue priority
- Edit job parameters before processing starts
- Pause/resume individual jobs or entire queue
- Remove jobs from queue with confirmation
- **Scheduled Processing**: 
  - Set queue to process only during specific hours (e.g., 11 PM - 7 AM)
  - "Process when idle" mode (low CPU priority)
  - "Electricity cost optimization" (if user provides time-of-use rates)
- **Resume Capability**: 
  - Save progress state every 5% completion
  - If job fails/interrupted, resume from last checkpoint
  - Verify partial output before resuming

**File Handling & Safety**
- **Transfer Management** (for remote Plex libraries):
  - Detect if source file is on remote mount/network share
  - Copy to local working directory for transcoding
  - Show transfer progress with speed and ETA
  - Bandwidth throttling option (limit MB/s to avoid saturating connection)
  - After transcode, transfer back to original location
  - Delete original only after successful verification
- **Plex Integration**:
  - Automatically trigger Plex library scan for updated files
  - Update Plex metadata if needed
  - Maintain Plex's watch status and custom metadata

**Safety & Backup Features**
- **Dry Run Mode**: 
  - Simulate entire transcode operation
  - Show expected file size, encoding time estimate, and final specs
  - No files are modified
- **Automatic Backup Before Transcode**:
  - Optional: Create backup copy before starting
  - Store in user-specified backup location
  - Auto-cleanup after X days or manual verification
- **Rollback Function**:
  - Move original to temporary holding area instead of immediate deletion
  - Keep originals until user manually approves transcode quality
  - Batch "approve and cleanup" for verified transcodes
  - "Reject and restore" to revert to original
- **Integrity Verification**:
  - After transcode completes, attempt to open file with FFprobe
  - Verify expected codec, resolution, and duration match
  - Optional: Generate and compare video checksums for sample frames
  - Only delete original after verification passes
  - Flag failed transcodes prominently with error details

### 4. Distributed Transcoding Architecture

**Worker Server Management**
- Support for multiple transcode servers (local Mac + remote Linux VPS/servers)
- Add server interface:
  - Hostname/IP address input
  - SSH credentials (username, password/key)
  - Server role: CPU-only or GPU-accelerated
  - Custom server nickname/label
  - Connection test button (verify SSH and dependencies)
- **Auto-Setup Script**:
  - When adding new Linux server, offer "Auto-Configure" option
  - SSH into server and run provisioning script:
    - Detect Linux distro (Ubuntu, Debian, CentOS, etc.)
    - Install FFmpeg with hardware acceleration (if GPU detected)
    - Install Python 3.11+ and required dependencies
    - Configure firewall rules for secure communication
    - Set up worker service (systemd) for persistent operation
    - Generate and exchange SSH keys for secure, password-free access
    - Test encode a sample file to verify setup
  - Display setup progress with detailed logs
  - Validate successful setup before adding to pool

**Job Distribution & Load Balancing**
- **Intelligent Job Assignment**:
  - Detect server capabilities (CPU cores, GPU presence, available RAM)
  - Assign jobs based on:
    - Current server load (query CPU/GPU usage)
    - Job requirements (4K needs more resources than 720p)
    - Hardware acceleration match (assign HEVC to NVENC-capable servers)
    - Network proximity (prefer local server for small jobs)
  - Manual override: Assign specific job to specific server
- **Load Monitoring Dashboard**:
  - Real-time view of all servers and their current jobs
  - Resource utilization graphs (CPU, GPU, RAM, disk I/O)
  - Network throughput for file transfers
  - Queue depth per server
  - Temperature monitoring (if available)

**Failover & Reliability**
- **Automatic Failover**:
  - Detect when worker server goes offline (heartbeat monitoring)
  - Automatically reassign in-progress job to another available server
  - Resume from last checkpoint if possible, or restart job
  - Notify user of failover event with details
- **Health Checks**:
  - Periodic connection tests to all workers
  - Automatic retry logic for transient network issues
  - Mark servers as "unhealthy" after repeated failures
  - User notification when intervention needed

**Cost Tracking (for Cloud Workers)**
- Track compute time per job and per server
- User inputs hourly cost rate for cloud VPS
- Dashboard showing:
  - Total compute hours this month
  - Estimated cost breakdown by server
  - Cost per job (most/least expensive jobs)
  - Projected monthly cost based on current usage
  - Cost savings from optimization (storage saved vs compute cost)
- Export cost reports for accounting

### 5. Monitoring, Reporting & Notifications

**Real-Time Transcode Dashboard**
- Live view of all active transcode jobs with:
  - Progress bar with percentage completion
  - Estimated time remaining (dynamic based on actual speed)
  - Current encoding speed (fps being processed)
  - Assigned server/worker
  - Source file details and target specs
  - Real-time file size preview
  - Resource usage (CPU/GPU on assigned server)
- Expandable detail view for each job showing:
  - FFmpeg command being executed
  - Live log output (truncated, full log available)
  - Current frame being processed
  - Quality metrics (if available)

**Historical Analytics**
- **Statistics Dashboard**:
  - Total storage saved since app installation
  - Number of files processed (by day, week, month)
  - Most common transcode operations (chart)
  - Average transcode speed over time
  - Server performance comparison
  - Success rate (completed vs failed jobs)
- **Charts & Visualizations**:
  - Storage saved over time (line graph)
  - Codec distribution before/after optimization (pie charts)
  - Resolution breakdown before/after (bar graphs)
  - Processing timeline (Gantt-style view of job history)
- Export all analytics data as reports

**Notifications & Alerts**
- **Email Notifications**:
  - Batch job completion summary
  - Individual job failures with error details
  - Server offline alerts
  - Storage saving milestones
  - User-configurable: daily digest or immediate alerts
- **macOS Push Notifications**:
  - Native notification center integration
  - Job completion alerts (for jobs > X minutes)
  - Error notifications with actionable buttons
  - Summary notifications for batch operations
- **Webhook Support**:
  - Configure webhook URLs for external integrations
  - JSON payload with job details on completion/failure
  - Use cases: Discord bot, Home Assistant, custom dashboards

**Before/After Comparison Tools**
- **Visual Comparison Player**:
  - Side-by-side video player (original vs transcoded)
  - Synchronized playback with frame accuracy
  - A/B quick toggle for same-frame comparison
  - Zoom tools for pixel-level inspection
- **Statistical Comparison**:
  - File size reduction (GB and percentage)
  - Bitrate changes (video and audio separately)
  - Quality metrics (PSNR, SSIM if calculated)
  - Encoding time and cost (if applicable)
  - Compatibility improvements listed

### 6. Advanced Library Management

**Batch Metadata Editing**
- Select multiple files and edit Plex metadata in bulk:
  - Update titles, descriptions, release dates
  - Assign genres, collections, tags
  - Set posters and backgrounds (bulk upload)
  - Modify audio/subtitle track preferences
- Changes pushed directly to Plex server
- Undo capability for accidental bulk edits

**Custom Tagging System**
- Create custom tag categories beyond Plex's defaults:
  - Example tags: "Needs Upgrade", "Transcode Pending", "Archive Quality", "Demo Material"
- Apply tags to files directly in the app
- Filter and search by custom tags
- Tags stored in local database, optionally synced to Plex
- Bulk tag operations

**Collection Builder**
- Automatically create Plex collections based on file attributes:
  - "All Dolby Atmos Movies"
  - "4K HDR Content"
  - "High Bitrate Films"
  - "Recent Additions This Month"
- Schedule collection updates (daily, weekly)
- Custom collection rules using filter builder
- Push collections directly to Plex server

**Library Health Dashboard**
- Comprehensive overview of entire media library:
  - **Codec Distribution**: Pie chart of H.264 vs H.265 vs AV1 vs others
  - **Resolution Breakdown**: Percentage of 4K, 1080p, 720p, SD
  - **Storage Usage by Quality Tier**: Show how much space each resolution consumes
  - **Audio Format Distribution**: Breakdown of Atmos, DTS, AAC, etc.
  - **Average Bitrates**: By resolution tier, compared to recommended standards
  - **Container Format Usage**: MKV vs MP4 vs others
  - **Library Growth Over Time**: Chart showing content additions per month
  - **HDR Content Percentage**: How much of 4K library is HDR
- Identify anomalies and inconsistencies automatically
- Export health report as PDF

### 7. Integration & Extensibility

**API Access**
- RESTful API for external tools to:
  - Query library statistics and file details
  - Queue transcode jobs programmatically
  - Check job status and history
  - Retrieve analytics data
- API authentication with token-based security
- Comprehensive API documentation with examples
- Rate limiting to prevent abuse

**Webhook Support**
- Configure webhooks for various events:
  - Job completion (with details)
  - Job failure (with error logs)
  - Server status changes
  - Library analysis completion
  - Storage milestones reached
- Custom webhook payloads with user-defined data
- Webhook testing interface in settings

**Import/Export Configurations**
- Export entire app configuration as JSON:
  - Server settings
  - Preset profiles
  - Filter presets
  - Custom tags
  - Scheduling rules
- Import configurations on new installation
- Share configurations with community

## User Interface Design Requirements

### Design Language (Reference: sample_designs folder)

The UI must achieve a **10/10 polish level** by implementing:

1. **Modern, Clean Aesthetic**
   - Ample whitespace and breathing room
   - Consistent 8px grid system
   - Subtle shadows and depth (elevation layers)
   - Smooth, purposeful animations (300ms standard transitions)
   - Professional typography hierarchy (SF Pro for macOS)

2. **Responsive Layout Patterns**
   - Master-detail view for file browsing (table/grid + detail panel)
   - Collapsible sidebars for filters and navigation
   - Adaptive layouts that reflow based on window size
   - Minimum window size: 1280x720, optimal: 1920x1080

3. **Color System**
   - Primary brand color with carefully chosen accents
   - Quality tier indicators:
     - Green: Optimal/efficient encoding
     - Yellow: Medium quality/opportunity for improvement
     - Red: Inefficient/needs attention
     - Blue: Processing/in-progress
   - Dark mode with OLED-friendly true blacks
   - Light mode with subtle background textures

4. **Data Visualization**
   - Interactive charts using Chart framework (SwiftUI)
   - Animated data transitions when filters change
   - Hover tooltips with detailed breakdowns
   - Zoomable/pannable graphs for large datasets

5. **Micro-Interactions**
   - Button hover states with subtle scale/shadow changes
   - Progress indicators with fluid animations
   - Success/error states with visual feedback (checkmarks, error icons)
   - Drag-and-drop visual feedback
   - Loading skeletons for async data

6. **Information Hierarchy**
   - Critical data prominently displayed
   - Secondary details accessible but not overwhelming
   - Expandable detail sections ("Show More" patterns)
   - Context-aware action buttons (only show relevant options)

7. **Native macOS Patterns**
   - Title bar integration with toolbar
   - Split view controllers for multi-pane layouts
   - Context menus (right-click) for quick actions
   - Keyboard shortcuts for power users
   - Touch Bar support (if applicable)
   - Accessibility: VoiceOver support, Dynamic Type, keyboard navigation

### Specific UI Components to Implement

- **File Browser**: Hybrid table/card view with smooth transitions
- **Filter Sidebar**: Collapsible panel with grouped filter controls
- **Transcode Modal**: Multi-step wizard with preview
- **Server Management Panel**: Card-based layout with status indicators
- **Dashboard**: Widget-based layout with draggable/resizable panels
- **Job Queue**: List view with expandable detail rows
- **Settings**: Organized tab interface with search

## Implementation Requirements

### No Shortcuts - Production Quality Standards

This is not a prototype or MVP. Every feature listed must be:

1. **Fully Implemented**: No placeholder text or "TODO" comments in production code
2. **Error Handled**: Comprehensive try-catch blocks, user-friendly error messages, logging
3. **Tested**: Core functionality must be validated (manual testing at minimum)
4. **Optimized**: Profile and optimize hot paths (large library loading, UI rendering)
5. **Documented**: Code comments for complex logic, README with setup instructions, user guide

### Code Quality Standards

- **Swift**: Follow Swift API Design Guidelines, use modern Swift features (async/await, Combine)
- **Python**: PEP 8 compliance, type hints throughout, docstrings for public functions
- **Architecture**: Clear separation of concerns (Model-View-ViewModel for Swift, layered architecture for Python)
- **Dependencies**: Minimize external dependencies, document all requirements
- **Configuration**: Environment-based config files (dev, staging, production)
- **Logging**: Structured logging with appropriate log levels (debug, info, warn, error)
- **Security**: Secure credential storage (Keychain for macOS), input validation, SQL injection prevention

### Performance Requirements

- Load library of 10,000+ items in < 5 seconds (with caching)
- UI remains responsive during background operations (async/await for I/O)
- Transcode job assignment latency < 1 second
- Real-time dashboard updates at 2fps minimum (every 500ms)
- Memory usage: < 500MB for typical library, graceful degradation for large libraries

### Platform Requirements

- **macOS**: Support macOS 13.0 (Ventura) and later
- **Plex**: Support Plex Media Server v1.30.0 and later
- **Worker Servers**: Ubuntu 20.04+, Debian 11+, CentOS 8+

## Development Phases

### Phase 1: Foundation (Core Infrastructure)
1. Project setup: Swift app with Python backend service
2. Plex API integration and authentication
3. Database schema and caching layer
4. Basic UI framework and navigation structure
5. FFmpeg integration and local transcoding

### Phase 2: Core Features
1. Media library visualization and data table
2. Filtering and sorting implementation
3. Basic transcode interface (single file)
4. Preset profiles system
5. Job queue management

### Phase 3: Intelligence Layer
1. Smart storage recommendations engine
2. Duplicate detection algorithm
3. Quality gap analysis
4. Codec compatibility matrix

### Phase 4: Distributed System
1. Worker server management interface
2. Auto-setup scripts for Linux servers
3. Job distribution and load balancing
4. Failover and health monitoring
5. Cost tracking for cloud workers

### Phase 5: Advanced Features
1. Quality comparison preview system
2. Batch metadata editing
3. Custom tagging and collection builder
4. Library health dashboard
5. Historical analytics and reporting

### Phase 6: Polish & Integration
1. Notification system (email, push, webhooks)
2. Before/after comparison tools
3. API implementation
4. UI refinement and animations
5. Comprehensive testing and bug fixes

### Phase 7: Documentation & Release
1. User guide and tutorials
2. API documentation
3. Installation scripts and packages
4. Community preset sharing platform
5. Initial release preparation

## Success Criteria

The project is complete when:

1. ✅ All listed features are fully implemented and functional
2. ✅ Application handles edge cases gracefully (network failures, corrupted files, server crashes)
3. ✅ UI achieves 10/10 polish level as defined in design requirements
4. ✅ Performance meets specified benchmarks
5. ✅ Code is documented and follows quality standards
6. ✅ User can successfully:
   - Connect to Plex server
   - Analyze entire library
   - Filter and find specific content
   - Transcode files locally
   - Add and auto-configure remote worker servers
   - Monitor jobs in real-time
   - Review analytics and optimization recommendations
7. ✅ No critical bugs or data loss scenarios
8. ✅ Installation process is straightforward with clear instructions

## Design Inspiration Reference

The `sample_designs` folder contains UI mockups created with Google Stitch. Use these as **inspiration** for:
- Layout patterns and information architecture
- Color schemes and visual hierarchy
- Component styling and interactions
- Responsive design approaches

**Do not blindly replicate** these designs. Instead:
- Extract the principles: spacing, contrast, flow
- Adapt patterns to native macOS components
- Improve upon ideas where SwiftUI offers better solutions
- Maintain consistency with macOS Human Interface Guidelines

The goal is a **native macOS experience** that feels familiar yet refined, leveraging SwiftUI's capabilities while drawing from the modern, responsive aesthetic shown in the samples.

---

## Development Philosophy

This is a **premium, professional-grade application**. Every interaction, every transition, every error message should reflect thoughtful design:

- Plan before coding (architecture diagrams, data models)
- Implement incrementally with validation at each step
- Refactor when code becomes messy
- Test thoroughly, especially edge cases
- Polish the details (icons, spacing, timing)

The result should be something you'd be proud to ship commercially. No compromises on quality.
