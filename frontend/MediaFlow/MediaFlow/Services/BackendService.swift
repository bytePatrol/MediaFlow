import Foundation

class BackendService {
    let client: APIClient

    init(baseURL: String = "http://localhost:9876") {
        self.client = APIClient(baseURL: baseURL)
    }

    // MARK: - Plex OAuth
    func createPlexPin() async throws -> PlexPinResponse {
        return try await client.post("/api/plex/auth/pin")
    }

    func checkPlexPinStatus(pinId: Int) async throws -> PlexAuthStatus {
        return try await client.get("/api/plex/auth/pin/\(pinId)/status")
    }

    func discoverPlexServers(token: String) async throws -> PlexDiscoverResponse {
        return try await client.post("/api/plex/auth/discover", body: ["token": token])
    }

    // MARK: - Plex
    func connectPlex(url: String, token: String) async throws -> PlexServerInfo {
        struct ConnectRequest: Codable { let url: String; let token: String }
        return try await client.post("/api/plex/connect", body: ConnectRequest(url: url, token: token))
    }

    func updatePlexServerSSH(id: Int, request: PlexServerSSHRequest) async throws -> PlexServerInfo {
        return try await client.put("/api/plex/servers/\(id)/ssh", body: request)
    }

    func testPlexServerSSH(id: Int) async throws -> SSHTestResponse {
        return try await client.post("/api/plex/servers/\(id)/test-ssh")
    }

    func getPlexServers() async throws -> [PlexServerInfo] {
        return try await client.get("/api/plex/servers")
    }

    func syncPlexServer(id: Int) async throws -> SyncResponse {
        return try await client.post("/api/plex/servers/\(id)/sync")
    }

    // MARK: - Library
    func getLibraryItems(page: Int = 1, pageSize: Int = 50, queryItems: [URLQueryItem] = []) async throws -> PaginatedMediaResponse {
        var items = queryItems
        items.append(URLQueryItem(name: "page", value: "\(page)"))
        items.append(URLQueryItem(name: "page_size", value: "\(pageSize)"))
        return try await client.get("/api/library/items", queryItems: items)
    }

    func getFilteredItemIds(queryItems: [URLQueryItem]) async throws -> FilteredItemIdsResponse {
        return try await client.get("/api/library/item-ids", queryItems: queryItems)
    }

    func getLibraryStats() async throws -> LibraryStats {
        return try await client.get("/api/library/stats")
    }

    func getLibrarySections() async throws -> [LibrarySection] {
        return try await client.get("/api/library/sections")
    }

    // MARK: - Transcode
    func createTranscodeJobs(request: TranscodeJobCreateRequest) async throws -> TranscodeJobCreateResponse {
        return try await client.post("/api/transcode/jobs", body: request)
    }

    func getTranscodeJobs(status: String? = nil, page: Int = 1) async throws -> PaginatedJobResponse {
        var items: [URLQueryItem] = [URLQueryItem(name: "page", value: "\(page)")]
        if let status = status { items.append(URLQueryItem(name: "status", value: status)) }
        return try await client.get("/api/transcode/jobs", queryItems: items)
    }

    func getQueueStats() async throws -> QueueStats {
        return try await client.get("/api/transcode/queue/stats")
    }

    // MARK: - Presets
    func getPresets() async throws -> [TranscodePreset] {
        return try await client.get("/api/presets/")
    }

    // MARK: - Workers
    func getWorkerServers() async throws -> [WorkerServer] {
        return try await client.get("/api/servers/")
    }

    func addWorkerServer(request: AddWorkerServerRequest) async throws -> WorkerServer {
        return try await client.post("/api/servers/", body: request)
    }

    func updateWorkerServer(id: Int, request: UpdateWorkerServerRequest) async throws -> WorkerServer {
        return try await client.put("/api/servers/\(id)", body: request)
    }

    func deleteWorkerServer(id: Int) async throws {
        try await client.delete("/api/servers/\(id)")
    }

    func testWorkerServer(id: Int) async throws -> SSHTestResponse {
        return try await client.post("/api/servers/\(id)/test")
    }

    func provisionServer(id: Int, installGpu: Bool = false) async throws -> ProvisionTriggerResponse {
        struct ProvisionRequest: Codable { let installGpu: Bool }
        return try await client.post("/api/servers/\(id)/provision", body: ProvisionRequest(installGpu: installGpu))
    }

    func triggerBenchmark(serverId: Int) async throws -> BenchmarkTriggerResponse {
        return try await client.post("/api/servers/\(serverId)/benchmark")
    }

    func getBenchmarks(serverId: Int) async throws -> [BenchmarkResult] {
        return try await client.get("/api/servers/\(serverId)/benchmarks")
    }

    func getAvailableServers() async throws -> [ServerPickerItem] {
        return try await client.get("/api/servers/available")
    }

    func getServerStatus(id: Int) async throws -> ServerStatus {
        return try await client.get("/api/servers/\(id)/status")
    }

    func getServerEstimate(serverId: Int, fileSizeBytes: Int, durationMs: Int) async throws -> ServerEstimateResponse {
        let items = [
            URLQueryItem(name: "file_size_bytes", value: "\(fileSizeBytes)"),
            URLQueryItem(name: "duration_ms", value: "\(durationMs)"),
        ]
        return try await client.get("/api/servers/\(serverId)/estimate", queryItems: items)
    }

    // MARK: - Cloud GPU
    func deployCloudGPU(request: CloudDeployRequest) async throws -> CloudDeployResponse {
        return try await client.post("/api/cloud/deploy", body: request)
    }

    func teardownCloudGPU(serverId: Int) async throws {
        try await client.delete("/api/cloud/\(serverId)")
    }

    func getCloudPlans() async throws -> [CloudPlanInfo] {
        return try await client.get("/api/cloud/plans")
    }

    func getCloudCostSummary() async throws -> CloudCostSummary {
        return try await client.get("/api/cloud/cost-summary")
    }

    func getCloudSettings() async throws -> CloudSettingsResponse {
        return try await client.get("/api/cloud/settings")
    }

    func updateCloudSettings(request: CloudSettingsUpdate) async throws -> CloudSettingsResponse {
        return try await client.put("/api/cloud/settings", body: request)
    }

    // MARK: - Path Mappings
    func getPathMappings() async throws -> [PathMapping] {
        let response: PathMappingsResponse = try await client.get("/api/settings/path_mappings")
        return response.value ?? []
    }

    func savePathMappings(_ mappings: [PathMapping]) async throws {
        let _: PathMappingsResponse = try await client.put("/api/settings/path_mappings", body: PathMappingsRequest(value: mappings))
    }

    // MARK: - Tags
    func getTags() async throws -> [TagInfo] {
        return try await client.get("/api/tags/")
    }

    func createTag(name: String, color: String) async throws -> TagInfo {
        struct CreateTagRequest: Codable { let name: String; let color: String }
        return try await client.post("/api/tags/", body: CreateTagRequest(name: name, color: color))
    }

    func updateTag(id: Int, name: String?, color: String?) async throws -> TagInfo {
        struct UpdateTagRequest: Codable { let name: String?; let color: String? }
        return try await client.put("/api/tags/\(id)", body: UpdateTagRequest(name: name, color: color))
    }

    func deleteTag(id: Int) async throws {
        try await client.delete("/api/tags/\(id)")
    }

    func applyTags(mediaItemIds: [Int], tagIds: [Int]) async throws -> BulkTagResponse {
        struct BulkTagRequest: Codable { let mediaItemIds: [Int]; let tagIds: [Int] }
        return try await client.post("/api/tags/apply", body: BulkTagRequest(mediaItemIds: mediaItemIds, tagIds: tagIds))
    }

    func removeTags(mediaItemIds: [Int], tagIds: [Int]) async throws -> BulkTagResponse {
        struct BulkTagRemoveRequest: Codable { let mediaItemIds: [Int]; let tagIds: [Int] }
        return try await client.post("/api/tags/remove", body: BulkTagRemoveRequest(mediaItemIds: mediaItemIds, tagIds: tagIds))
    }

    // MARK: - Analytics
    func getAnalyticsOverview() async throws -> AnalyticsOverview {
        return try await client.get("/api/analytics/overview")
    }

    func getStorageBreakdown() async throws -> StorageBreakdown {
        return try await client.get("/api/analytics/storage")
    }

    func getCodecDistribution() async throws -> CodecDistribution {
        return try await client.get("/api/analytics/codec-distribution")
    }

    // MARK: - Recommendations
    func getRecommendations(type: String? = nil) async throws -> [Recommendation] {
        var items: [URLQueryItem] = []
        if let type = type { items.append(URLQueryItem(name: "type", value: type)) }
        return try await client.get("/api/recommendations/", queryItems: items)
    }

    func generateRecommendations() async throws -> GenerateResponse {
        return try await client.post("/api/recommendations/generate")
    }

    func getRecommendationSummary() async throws -> RecommendationSummary {
        return try await client.get("/api/recommendations/summary")
    }

    func batchQueueRecommendations(ids: [Int], presetId: Int? = nil) async throws -> BatchQueueResponse {
        struct BatchQueueRequest: Codable { let recommendationIds: [Int]; let presetId: Int? }
        return try await client.post("/api/recommendations/batch-queue", body: BatchQueueRequest(recommendationIds: ids, presetId: presetId))
    }
}

struct BatchQueueResponse: Codable {
    let status: String
    let jobsCreated: Int
}

struct BulkTagResponse: Codable {
    let status: String
}

struct SyncResponse: Codable {
    let status: String
    let itemsSynced: Int
    let librariesSynced: Int
    let durationSeconds: Double
}

struct LibraryStats: Codable {
    let totalItems: Int
    let totalSize: Int
    let totalDurationMs: Int
    let codecBreakdown: [String: Int]
    let resolutionBreakdown: [String: Int]
    let hdrCount: Int
    let avgBitrate: Double
    let libraries: [[String: AnyCodable]]
}

struct LibrarySection: Codable, Identifiable {
    let id: Int
    let title: String
    let type: String
    let totalItems: Int
    let totalSize: Int
    let serverName: String
}

struct PaginatedJobResponse: Codable {
    let items: [TranscodeJob]
    let total: Int
    let page: Int
    let pageSize: Int
}

struct GenerateResponse: Codable {
    let status: String
    let recommendationsGenerated: Int
}

struct PlexPinResponse: Codable {
    let pinId: Int
    let authUrl: String
}

struct PlexAuthStatus: Codable {
    let status: String
    let authToken: String?
    let serversDiscovered: Int?
    let errorMessage: String?
}

struct PlexDiscoverResponse: Codable {
    let status: String
    let servers: [PlexServerInfo]
}

struct AddWorkerServerRequest: Codable {
    let name: String
    let hostname: String
    let port: Int
    let sshUsername: String?
    let isLocal: Bool
    let pathMappings: [PathMapping]?
}

struct UpdateWorkerServerRequest: Codable {
    var name: String?
    var hostname: String?
    var port: Int?
    var sshUsername: String?
    var maxConcurrentJobs: Int?
    var isEnabled: Bool?
    var workingDirectory: String?
    var pathMappings: [PathMapping]?
}

struct PlexServerSSHRequest: Codable {
    var sshHostname: String?
    var sshPort: Int = 22
    var sshUsername: String?
    var sshKeyPath: String?
    var sshPassword: String?
    var benchmarkPath: String?
}

struct SSHTestResponse: Codable {
    let status: String
    let message: String
}
