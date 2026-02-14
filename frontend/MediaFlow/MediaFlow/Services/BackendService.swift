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

    func probeFile(path: String) async throws -> ProbeResult {
        struct ProbeReq: Codable { let filePath: String }
        return try await client.post("/api/transcode/probe", body: ProbeReq(filePath: path))
    }

    func createManualTranscodeJob(request: ManualTranscodeRequest) async throws -> TranscodeJobCreateResponse {
        return try await client.post("/api/transcode/manual", body: request)
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

    func exportPreset(id: Int) async throws -> [String: AnyCodable] {
        return try await client.get("/api/presets/\(id)/export")
    }

    func importPreset(data: [String: AnyCodable]) async throws -> TranscodePreset {
        return try await client.post("/api/presets/import", body: data)
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

    // MARK: - Notifications
    func getNotificationConfigs() async throws -> [NotificationConfigInfo] {
        return try await client.get("/api/notifications/")
    }

    func createNotificationConfig(request: NotificationConfigCreateRequest) async throws -> NotificationConfigInfo {
        return try await client.post("/api/notifications/", body: request)
    }

    func updateNotificationConfig(id: Int, request: NotificationConfigUpdateRequest) async throws -> NotificationConfigInfo {
        return try await client.put("/api/notifications/\(id)", body: request)
    }

    func deleteNotificationConfig(id: Int) async throws {
        try await client.delete("/api/notifications/\(id)")
    }

    func testNotification(id: Int) async throws -> TestNotificationResponse {
        return try await client.post("/api/notifications/\(id)/test")
    }

    // MARK: - Collections
    func getCollections(serverId: Int) async throws -> [CollectionInfo] {
        let items = [URLQueryItem(name: "server_id", value: "\(serverId)")]
        return try await client.get("/api/collections/", queryItems: items)
    }

    func createCollection(request: CollectionCreateRequest) async throws -> CollectionCreateResponse {
        return try await client.post("/api/collections/", body: request)
    }

    func addToCollection(collectionId: String, request: CollectionAddRequest) async throws -> CollectionCreateResponse {
        return try await client.post("/api/collections/\(collectionId)/add", body: request)
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

    func getResolutionDistribution() async throws -> ResolutionDistribution {
        return try await client.get("/api/analytics/resolution-distribution")
    }

    func getSavingsHistory(days: Int = 30) async throws -> [SavingsHistoryPoint] {
        let items = [URLQueryItem(name: "days", value: "\(days)")]
        return try await client.get("/api/analytics/savings-history", queryItems: items)
    }

    func getTrends(days: Int = 30) async throws -> TrendsResponse {
        let items = [URLQueryItem(name: "days", value: "\(days)")]
        return try await client.get("/api/analytics/trends", queryItems: items)
    }

    func getPredictions() async throws -> PredictionResponse {
        return try await client.get("/api/analytics/predictions")
    }

    func getServerPerformance() async throws -> [ServerPerformanceInfo] {
        return try await client.get("/api/analytics/server-performance")
    }

    func getHealthScore() async throws -> HealthScoreResponse {
        return try await client.get("/api/analytics/health-score")
    }

    func getTopOpportunities() async throws -> [SavingsOpportunity] {
        return try await client.get("/api/analytics/top-opportunities")
    }

    func getTrendSparkline(metric: String, days: Int = 30) async throws -> [SparklinePoint] {
        let items = [
            URLQueryItem(name: "metric", value: metric),
            URLQueryItem(name: "days", value: "\(days)"),
        ]
        return try await client.get("/api/analytics/trend-sparkline", queryItems: items)
    }

    func getStorageTimeline(days: Int = 90) async throws -> [StorageTimelinePoint] {
        let items = [URLQueryItem(name: "days", value: "\(days)")]
        return try await client.get("/api/analytics/storage-timeline", queryItems: items)
    }

    func downloadHealthReport() async throws -> Data {
        return try await client.getRaw("/api/analytics/report/pdf")
    }

    // MARK: - Recommendations
    func getRecommendations(type: String? = nil, libraryId: Int? = nil) async throws -> [Recommendation] {
        var items: [URLQueryItem] = []
        if let type = type { items.append(URLQueryItem(name: "type", value: type)) }
        if let libraryId = libraryId { items.append(URLQueryItem(name: "library_id", value: "\(libraryId)")) }
        return try await client.get("/api/recommendations/", queryItems: items)
    }

    func generateRecommendations() async throws -> GenerateResponse {
        return try await client.post("/api/recommendations/generate")
    }

    func analyzeLibrary(libraryId: Int) async throws -> GenerateResponse {
        return try await client.post("/api/recommendations/analyze/\(libraryId)")
    }

    func getRecommendationSummary() async throws -> RecommendationSummary {
        return try await client.get("/api/recommendations/summary")
    }

    func batchQueueRecommendations(ids: [Int], presetId: Int? = nil) async throws -> BatchQueueResponse {
        struct BatchQueueRequest: Codable { let recommendationIds: [Int]; let presetId: Int? }
        return try await client.post("/api/recommendations/batch-queue", body: BatchQueueRequest(recommendationIds: ids, presetId: presetId))
    }

    func getAnalysisHistory(limit: Int = 20) async throws -> [AnalysisRunInfo] {
        let items = [URLQueryItem(name: "limit", value: "\(limit)")]
        return try await client.get("/api/recommendations/history", queryItems: items)
    }

    func getSavingsAchieved() async throws -> SavingsAchievedInfo {
        return try await client.get("/api/recommendations/savings")
    }

    // MARK: - Intelligence Settings
    func getIntelSetting(key: String) async throws -> AppSettingValue {
        return try await client.get("/api/settings/\(key)")
    }

    func setIntelSetting(key: String, value: String) async throws -> AppSettingValue {
        return try await client.put("/api/settings/\(key)", body: ["value": value])
    }

    // MARK: - Schedule Settings
    func getScheduleSetting(key: String) async throws -> AppSettingValue {
        return try await client.get("/api/settings/\(key)")
    }

    func setScheduleSetting(key: String, value: String) async throws -> AppSettingValue {
        return try await client.put("/api/settings/\(key)", body: ["value": value])
    }

    // MARK: - Filter Presets
    func getFilterPresets() async throws -> [FilterPresetInfo] {
        return try await client.get("/api/filter-presets/")
    }

    func createFilterPreset(name: String, filters: [String: AnyCodable]) async throws -> FilterPresetInfo {
        return try await client.post("/api/filter-presets/", body: FilterPresetCreateRequest(name: name, filterJson: filters))
    }

    func deleteFilterPreset(id: Int) async throws {
        try await client.delete("/api/filter-presets/\(id)")
    }

    // MARK: - Notification Events
    func getNotificationEvents() async throws -> [NotificationEventInfo] {
        return try await client.get("/api/notifications/events")
    }

    func getNotificationHistory(limit: Int = 50) async throws -> NotificationHistoryResponse {
        let items = [URLQueryItem(name: "limit", value: "\(limit)")]
        return try await client.get("/api/notifications/history", queryItems: items)
    }

    // MARK: - Webhook Sources
    func getWebhookSources() async throws -> [WebhookSourceInfo] {
        return try await client.get("/api/webhooks/sources")
    }

    func createWebhookSource(request: WebhookSourceCreateRequest) async throws -> WebhookSourceInfo {
        return try await client.post("/api/webhooks/sources", body: request)
    }

    func deleteWebhookSource(id: Int) async throws {
        try await client.delete("/api/webhooks/sources/\(id)")
    }

    // MARK: - Watch Folders
    func getWatchFolders() async throws -> [WatchFolderInfo] {
        return try await client.get("/api/watch-folders/")
    }

    func createWatchFolder(request: WatchFolderCreateRequest) async throws -> WatchFolderInfo {
        return try await client.post("/api/watch-folders/", body: request)
    }

    func deleteWatchFolder(id: Int) async throws {
        try await client.delete("/api/watch-folders/\(id)")
    }

    func toggleWatchFolder(id: Int) async throws -> WatchFolderInfo {
        return try await client.post("/api/watch-folders/\(id)/toggle")
    }
}

struct AppSettingValue: Codable {
    let key: String
    var value: String?
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
    var serverId: Int?
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

// MARK: - Notification Models

struct NotificationConfigInfo: Codable, Identifiable {
    let id: Int
    let type: String
    let name: String
    var configJson: [String: AnyCodable]?
    var events: [String]?
    var isEnabled: Bool
}

struct NotificationConfigCreateRequest: Codable {
    let type: String
    let name: String
    let config: [String: AnyCodable]
    let events: [String]
    let isEnabled: Bool
}

struct NotificationConfigUpdateRequest: Codable {
    var name: String?
    var config: [String: AnyCodable]?
    var events: [String]?
    var isEnabled: Bool?
}

struct TestNotificationResponse: Codable {
    let status: String
    let message: String
}

// MARK: - Collection Models

struct CollectionInfo: Codable, Identifiable {
    let id: String
    let title: String
    let sectionKey: String
    let sectionTitle: String
    let itemCount: Int
    var thumbUrl: String?
}

struct CollectionCreateRequest: Codable {
    let serverId: Int
    let libraryId: Int
    let title: String
    let mediaItemIds: [Int]
}

struct CollectionAddRequest: Codable {
    let serverId: Int
    let mediaItemIds: [Int]
}

struct CollectionCreateResponse: Codable {
    let status: String
    var collectionId: String?
    let title: String
    let itemsAdded: Int
}
