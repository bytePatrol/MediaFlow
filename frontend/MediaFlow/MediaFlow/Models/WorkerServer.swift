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
