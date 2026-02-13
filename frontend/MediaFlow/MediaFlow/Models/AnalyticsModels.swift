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
