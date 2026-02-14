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
    var cloudCostUsd: Double?
    var retryCount: Int = 0
    var maxRetries: Int = 3
    var validationStatus: String?

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

    var formattedSourceSize: String {
        guard let size = sourceSize else { return "--" }
        return Self.formatBytes(size)
    }

    var formattedOutputSize: String {
        guard let size = outputSize else { return "--" }
        return Self.formatBytes(size)
    }

    var sizeReductionPercent: Double? {
        guard let src = sourceSize, let out = outputSize, src > 0 else { return nil }
        return (1.0 - Double(out) / Double(src)) * 100.0
    }

    var formattedDuration: String {
        guard let start = startedAt, let end = completedAt else { return "--" }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let startDate = fmt.date(from: start),
              let endDate = fmt.date(from: end) else { return "--" }
        let seconds = Int(endDate.timeIntervalSince(startDate))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%dh %dm %ds", h, m, s)
        }
        return String(format: "%dm %ds", m, s)
    }

    var formattedCloudCost: String {
        guard let cost = cloudCostUsd else { return "--" }
        return String(format: "$%.4f", cost)
    }

    private static func formatBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.2f GB", gb)
        }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", mb)
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

struct ProbeResult: Codable {
    let filePath: String
    let fileSize: Int
    let durationSeconds: Double
    let videoCodec: String?
    let resolution: String?
    let bitrate: Int?
    let audioCodec: String?
    let audioChannels: Int?

    var formattedSize: String {
        let gb = Double(fileSize) / 1_073_741_824
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        let mb = Double(fileSize) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    var formattedDuration: String {
        let total = Int(durationSeconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%dh %dm", h, m) }
        return String(format: "%dm %ds", m, s)
    }

    var formattedBitrate: String {
        guard let br = bitrate, br > 0 else { return "--" }
        let mbps = Double(br) / 1_000_000
        if mbps >= 1 { return String(format: "%.1f Mbps", mbps) }
        let kbps = Double(br) / 1_000
        return String(format: "%.0f Kbps", kbps)
    }
}

struct ManualTranscodeRequest: Codable {
    let filePath: String
    var fileSize: Int?
    var config: [String: AnyCodable]?
    var presetId: Int?
    var priority: Int = 10
    var preferredWorkerId: Int?
}
