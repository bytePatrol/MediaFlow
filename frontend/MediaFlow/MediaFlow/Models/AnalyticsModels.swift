import Foundation

// MARK: - Trends

struct TrendData: Codable, Identifiable {
    var id: String { metric }
    let metric: String
    let currentValue: Double
    let previousValue: Double
    let changePct: Double
    let direction: String
}

struct TrendsResponse: Codable {
    let periodDays: Int
    let trends: [TrendData]
}

// MARK: - Predictions

struct PredictionResponse: Codable {
    let dailyRate: Double
    let predicted30d: Double
    let predicted90d: Double
    let predicted365d: Double
    let confidence: Double
}

// MARK: - Server Performance

struct ServerPerformanceInfo: Codable, Identifiable {
    var id: Int { serverId }
    let serverId: Int
    let serverName: String
    let totalJobs: Int
    let avgFps: Double?
    let avgCompression: Double?
    let totalTimeHours: Double
    let failureRate: Double
    let isCloud: Bool
}

// MARK: - Health Score

struct HealthScoreResponse: Codable {
    let score: Int
    let modernCodecPct: Double
    let bitratePct: Double
    let containerPct: Double
    let audioPct: Double
    let grade: String
}

// MARK: - Savings Opportunity

struct SavingsOpportunity: Codable, Identifiable {
    var id: Int { mediaItemId }
    let mediaItemId: Int
    let title: String
    let fileSize: Int
    let estimatedSavings: Int
    let currentCodec: String?
    let recommendedCodec: String
}

// MARK: - Resolution Distribution

struct ResolutionDistribution: Codable {
    let resolutions: [String]
    let counts: [Int]
    let sizes: [Int]
}

// MARK: - Savings History

struct SavingsHistoryPoint: Codable, Identifiable {
    var id: String { date }
    let date: String
    let savings: Int
    let cumulativeSavings: Int
    let jobsCompleted: Int
}

// MARK: - Filter Preset

struct FilterPresetInfo: Codable, Identifiable {
    let id: Int
    let name: String
    let filterJson: [String: AnyCodable]?
    let createdAt: String?
    let updatedAt: String?
}

struct FilterPresetCreateRequest: Codable {
    let name: String
    let filterJson: [String: AnyCodable]
}

// MARK: - Notification Events

struct NotificationEventInfo: Codable, Identifiable {
    var id: String { event }
    let event: String
    let description: String
}

// MARK: - Notification History

struct NotificationLogInfo: Codable, Identifiable {
    let id: Int
    let event: String
    let channelType: String
    let channelName: String?
    let payloadJson: String?
    let status: String
    let errorMessage: String?
    let createdAt: String?
}

struct NotificationHistoryResponse: Codable {
    let items: [NotificationLogInfo]
    let total: Int
}

// MARK: - Sparkline

struct SparklinePoint: Codable, Identifiable {
    var id: String { date }
    let date: String
    let value: Int
}

// MARK: - Storage Timeline

struct StorageTimelinePoint: Codable, Identifiable {
    var id: String { date }
    let date: String
    let actualSize: Int
    let withoutTranscoding: Int
    let savings: Int
}

// MARK: - Webhook Sources

struct WebhookSourceInfo: Codable, Identifiable {
    let id: Int
    let name: String
    let sourceType: String
    var secret: String?
    var presetId: Int?
    var isEnabled: Bool = true
    var lastReceivedAt: String?
    var eventsReceived: Int = 0
}

struct WebhookSourceCreateRequest: Codable {
    let name: String
    let sourceType: String
    var presetId: Int?
}

// MARK: - Watch Folders

struct WatchFolderInfo: Codable, Identifiable {
    let id: Int
    let path: String
    var presetId: Int?
    var extensions: String = "mkv,mp4,avi,mov,ts,m4v,wmv"
    var delaySeconds: Int = 30
    var isEnabled: Bool = true
    var lastScanAt: String?
    var filesProcessed: Int = 0
}

struct WatchFolderCreateRequest: Codable {
    let path: String
    var presetId: Int?
    var extensions: String = "mkv,mp4,avi,mov,ts,m4v,wmv"
    var delaySeconds: Int = 30
}
