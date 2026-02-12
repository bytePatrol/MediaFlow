import Foundation

struct TranscodeJob: Identifiable, Codable {
    let id: Int
    var mediaItemId: Int?
    var presetId: Int?
    var workerServerId: Int?
    var configJson: [String: AnyCodable]?
    var status: String
    var statusDetail: String?
    var priority: Int = 0
    var progressPercent: Double = 0.0
    var currentFps: Double?
    var etaSeconds: Int?
    var sourcePath: String?
    var sourceSize: Int?
    var outputPath: String?
    var outputSize: Int?
    var ffmpegCommand: String?
    var ffmpegLog: String?
    var isDryRun: Bool = false
    var createdAt: String?
    var startedAt: String?
    var completedAt: String?
    var mediaTitle: String?

    var statusDisplayName: String {
        switch status {
        case "queued": return "Queued"
        case "transferring": return "Transferring"
        case "transcoding": return "Transcoding"
        case "verifying": return "Verifying"
        case "replacing": return "Replacing"
        case "completed": return "Completed"
        case "failed": return "Failed"
        case "cancelled": return "Cancelled"
        case "paused": return "Paused"
        default: return status.capitalized
        }
    }

    var isActive: Bool {
        ["transcoding", "transferring", "verifying", "replacing"].contains(status)
    }

    var formattedETA: String {
        guard let eta = etaSeconds, eta > 0 else { return "--" }
        let hours = eta / 3600
        let minutes = (eta % 3600) / 60
        let seconds = eta % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}

struct TranscodeJobCreateRequest: Codable {
    let mediaItemIds: [Int]
    var presetId: Int?
    var config: [String: AnyCodable]?
    var priority: Int = 0
    var isDryRun: Bool = false
    var preferredWorkerId: Int?
}

struct TranscodeJobCreateResponse: Codable {
    let status: String
    let jobsCreated: Int
    let jobIds: [Int]
}

struct QueueStats: Codable {
    let totalQueued: Int
    let totalActive: Int
    let totalCompleted: Int
    let totalFailed: Int
    let aggregateFps: Double
    let estimatedTotalTime: Int
    let availableWorkers: Int?
}
