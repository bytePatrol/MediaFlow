import Foundation

struct PathMapping: Codable, Identifiable {
    var id = UUID()
    var sourcePrefix: String
    var targetPrefix: String

    enum CodingKeys: String, CodingKey {
        case sourcePrefix, targetPrefix
    }
}

struct WorkerServer: Identifiable, Codable {
    let id: Int
    let name: String
    let hostname: String
    var port: Int = 22
    var sshUsername: String?
    var role: String = "transcode"
    var gpuModel: String?
    var cpuModel: String?
    var cpuCores: Int?
    var ramGb: Double?
    var hwAccelTypes: [String]?
    var maxConcurrentJobs: Int = 1
    var status: String = "offline"
    var lastHeartbeatAt: String?
    var hourlyCost: Double?
    var isLocal: Bool = false
    var isEnabled: Bool = true
    var workingDirectory: String = "/tmp/mediaflow"
    var pathMappings: [PathMapping]?
    var activeJobs: Int = 0
    var performanceScore: Double?
    var lastBenchmarkAt: String?
    // Cloud GPU fields
    var cloudProvider: String?
    var cloudInstanceId: String?
    var cloudPlan: String?
    var cloudRegion: String?
    var cloudCreatedAt: String?
    var cloudAutoTeardown: Bool = true
    var cloudIdleMinutes: Int = 30
    var cloudStatus: String?    // "creating", "bootstrapping", "active", "destroying", "destroyed"

    var isCloud: Bool { cloudProvider != nil }
}

struct ServerStatus: Codable {
    let id: Int
    let name: String
    let status: String
    var cpuPercent: Double?
    var gpuPercent: Double?
    var ramUsedGb: Double?
    var ramTotalGb: Double?
    var gpuTemp: Double?
    var fanSpeed: Int?
    var activeJobs: Int = 0
    var queuedJobs: Int = 0
    var uptimePercent: Double?
    var uploadMbps: Double?
    var downloadMbps: Double?
    var performanceScore: Double?
}

struct BenchmarkResult: Identifiable, Codable {
    let id: Int
    let workerServerId: Int
    var uploadMbps: Double?
    var downloadMbps: Double?
    var latencyMs: Double?
    var testFileSizeBytes: Int = 200_000_000
    var status: String
    var errorMessage: String?
    var startedAt: String?
    var completedAt: String?
    var createdAt: String?
}

struct BenchmarkTriggerResponse: Codable {
    let status: String
    var benchmarkId: Int?
    let message: String
}

struct ServerPickerItem: Identifiable, Codable {
    let id: Int
    let name: String
    let status: String
    var performanceScore: Double?
    var activeJobs: Int = 0
    var queuedJobs: Int = 0
    var maxConcurrentJobs: Int = 1
    var cpuModel: String?
    var gpuModel: String?
    var uploadMbps: Double?
    var downloadMbps: Double?
    var isLocal: Bool = false
}

struct ServerEstimateResponse: Codable {
    let serverId: Int
    let serverName: String
    var estimatedSeconds: Int?
    var estimatedDisplay: String = "--"
    var basedOnJobs: Int = 0
}

struct ProvisionTriggerResponse: Codable {
    let status: String
    let message: String
}

struct ProvisionProgress {
    let serverId: Int
    let progress: Int
    let step: String
    let message: String
}

struct CloudDeployProgress {
    let serverId: Int
    let step: String
    let progress: Int
    let message: String
}

// MARK: - Cloud GPU Models

struct CloudPlanInfo: Identifiable, Codable {
    var id: String { planId }
    let planId: String
    let gpuModel: String
    let vcpus: Int
    let ramMb: Int
    let gpuVramGb: Int
    let monthlyCost: Double
    let hourlyCost: Double
    let regions: [String]
}

struct CloudDeployRequest: Codable {
    let plan: String
    let region: String
    let idleMinutes: Int
    let autoTeardown: Bool
}

struct CloudDeployResponse: Codable {
    let status: String
    let serverId: Int
    let message: String
}

struct CloudCostRecordResponse: Codable, Identifiable {
    let id: Int
    var workerServerId: Int?
    var jobId: Int?
    let cloudProvider: String
    let cloudInstanceId: String
    let cloudPlan: String
    let hourlyRate: Double
    let startTime: String
    var endTime: String?
    var durationSeconds: Double?
    var costUsd: Double?
    let recordType: String
}

struct CloudCostSummary: Codable {
    let currentMonthTotal: Double
    let activeInstanceRunningCost: Double
    let monthlyCap: Double
    let instanceCap: Double
    let records: [CloudCostRecordResponse]
}

struct CloudSettingsResponse: Codable {
    let apiKeyConfigured: Bool
    let defaultPlan: String
    let defaultRegion: String
    let monthlySpendCap: Double
    let instanceSpendCap: Double
    let defaultIdleMinutes: Int
}

struct CloudSettingsUpdate: Codable {
    var vultrApiKey: String?
    var defaultPlan: String?
    var defaultRegion: String?
    var monthlySpendCap: Double?
    var instanceSpendCap: Double?
    var defaultIdleMinutes: Int?
}
