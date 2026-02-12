import SwiftUI
import Combine

struct TransferProgress {
    var direction: String = "download"  // "download" or "upload"
    var progress: Double = 0.0
    var speed: String = "--"
    var etaSeconds: Int = 0

    var formattedETA: String {
        guard etaSeconds > 0 else { return "--" }
        let m = etaSeconds / 60
        let s = etaSeconds % 60
        if m > 0 {
            return "\(m)m \(s)s"
        }
        return "\(s)s"
    }
}

@MainActor
class TranscodeViewModel: ObservableObject {
    @Published var jobs: [TranscodeJob] = []
    @Published var activeJobs: [TranscodeJob] = []
    @Published var queueStats: QueueStats?
    @Published var isLoading: Bool = false
    @Published var selectedFilter: JobFilter = .all
    @Published var totalJobs: Int = 0
    @Published var jobLogMessages: [Int: [String]] = [:]
    @Published var jobTransferProgress: [Int: TransferProgress] = [:]

    private let service: BackendService
    private var wsService: WebSocketService?

    enum JobFilter: String, CaseIterable {
        case all = "All Processing"
        case transcoding = "Transcoding"
        case completed = "Completed"
        case failed = "Failed"

        var icon: String {
            switch self {
            case .all: return "play.circle"
            case .transcoding: return "film"
            case .completed: return "checkmark.circle"
            case .failed: return "xmark.circle"
            }
        }

        var statusFilter: String? {
            switch self {
            case .all: return nil
            case .transcoding: return "queued,transferring,transcoding,verifying"
            case .completed: return "completed"
            case .failed: return "failed"
            }
        }
    }

    var hasWorkerIssue: Bool {
        let workers = queueStats?.availableWorkers ?? 0
        let queued = queueStats?.totalQueued ?? 0
        let active = queueStats?.totalActive ?? 0
        return workers == 0 && (queued > 0 || active > 0)
    }

    var queueStatusColor: Color {
        let workers = queueStats?.availableWorkers ?? 0
        let queued = queueStats?.totalQueued ?? 0
        let active = queueStats?.totalActive ?? 0
        if workers == 0 && (queued > 0 || active > 0) { return .mfWarning }
        if active > 0 { return .mfSuccess }
        if queued > 0 { return .mfPrimary }
        return .mfTextMuted
    }

    var queueStatusLabel: String {
        let workers = queueStats?.availableWorkers ?? 0
        let queued = queueStats?.totalQueued ?? 0
        let active = queueStats?.totalActive ?? 0
        if workers == 0 && (queued > 0 || active > 0) { return "No Workers" }
        if active > 0 { return "Processing" }
        if queued > 0 { return "Waiting" }
        return "Idle"
    }

    init(service: BackendService = BackendService()) {
        self.service = service
    }

    func connectWebSocket() {
        let ws = WebSocketService()
        ws.connect()
        setupWebSocket(ws)
    }

    func loadJobs() async {
        isLoading = true
        do {
            let response = try await service.getTranscodeJobs(status: selectedFilter.statusFilter)
            jobs = response.items
            totalJobs = response.total
            activeJobs = jobs.filter { $0.isActive }
        } catch {
            print("Failed to load jobs: \(error)")
        }
        isLoading = false
    }

    func loadQueueStats() async {
        do {
            queueStats = try await service.getQueueStats()
        } catch {
            print("Failed to load queue stats: \(error)")
        }
    }

    func cancelJob(_ jobId: Int) async {
        // Optimistically update UI immediately
        if let index = jobs.firstIndex(where: { $0.id == jobId }) {
            jobs[index].status = "cancelled"
            activeJobs = jobs.filter { $0.isActive }
        }
        jobTransferProgress.removeValue(forKey: jobId)

        let client = APIClient(baseURL: service.client.baseURL)
        struct UpdateReq: Codable { let status: String }
        struct UpdateResp: Codable { let status: String; let jobId: Int; let newStatus: String }
        let _: UpdateResp? = try? await client.patch("/api/transcode/jobs/\(jobId)", body: UpdateReq(status: "cancelled"))
        await loadJobs()
    }

    func pauseJob(_ jobId: Int) async {
        let client = APIClient(baseURL: service.client.baseURL)
        struct UpdateReq: Codable { let status: String }
        let _: [String: AnyCodable]? = try? await client.patch("/api/transcode/jobs/\(jobId)", body: UpdateReq(status: "paused"))
        await loadJobs()
    }

    func clearFinished() async {
        let client = APIClient(baseURL: service.client.baseURL)
        try? await client.delete("/api/transcode/jobs/finished?include_active=true")
        jobLogMessages.removeAll()
        jobTransferProgress.removeAll()
        await loadJobs()
        await loadQueueStats()
    }

    func clearCache() async -> String {
        let client = APIClient(baseURL: service.client.baseURL)
        try? await client.delete("/api/transcode/cache")
        return "Cache cleared"
    }

    func pauseAll() async {
        let pausable = jobs.filter { $0.isActive || $0.status == "queued" }
        for job in pausable {
            await pauseJob(job.id)
        }
        await loadQueueStats()
    }

    private func setupWebSocket(_ ws: WebSocketService) {
        self.wsService = ws

        ws.subscribe(to: "job.progress") { [weak self] msg in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let jobId = msg.data["job_id"]?.intValue,
                      let progress = msg.data["progress"]?.doubleValue else { return }
                if let index = self.jobs.firstIndex(where: { $0.id == jobId }) {
                    self.jobs[index].progressPercent = progress
                    self.jobs[index].currentFps = msg.data["fps"]?.doubleValue
                    self.jobs[index].etaSeconds = msg.data["eta_seconds"]?.intValue
                }
            }
        }

        ws.subscribe(to: "job.transfer_progress") { [weak self] msg in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let jobId = msg.data["job_id"]?.intValue else { return }
                var tp = TransferProgress()
                tp.direction = msg.data["direction"]?.stringValue ?? "download"
                tp.progress = msg.data["progress"]?.doubleValue ?? 0
                tp.speed = msg.data["speed"]?.stringValue ?? "--"
                tp.etaSeconds = msg.data["eta_seconds"]?.intValue ?? 0
                self.jobTransferProgress[jobId] = tp

                // Also append to log
                let pct = Int(tp.progress)
                let dir = tp.direction == "download" ? "Downloading" : "Uploading"
                let logLine = "\(dir) \(pct)% — \(tp.speed) — ETA \(tp.formattedETA)"
                self.jobLogMessages[jobId] = [logLine]  // Replace with latest line
            }
        }

        ws.subscribe(to: "job.status_changed") { [weak self] msg in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let jobId = msg.data["job_id"]?.intValue,
                   let status = msg.data["status"]?.stringValue,
                   let index = self.jobs.firstIndex(where: { $0.id == jobId }) {
                    self.jobs[index].status = status
                    self.activeJobs = self.jobs.filter { $0.isActive }
                    // Clear transfer progress when leaving transferring state
                    if status != "transferring" {
                        self.jobTransferProgress.removeValue(forKey: jobId)
                    }
                }
                await self.loadJobs()
            }
        }

        ws.subscribe(to: "job.log") { [weak self] msg in
            Task { @MainActor [weak self] in
                guard let self = self,
                      let jobId = msg.data["job_id"]?.intValue,
                      let message = msg.data["message"]?.stringValue else { return }
                var lines = self.jobLogMessages[jobId] ?? []
                lines.append(message)
                if lines.count > 20 { lines = Array(lines.suffix(20)) }
                self.jobLogMessages[jobId] = lines
            }
        }

        ws.subscribe(to: "job.failed") { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.loadJobs()
                await self?.loadQueueStats()
            }
        }

        ws.subscribe(to: "job.completed") { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.loadJobs()
                await self?.loadQueueStats()
            }
        }
    }
}
