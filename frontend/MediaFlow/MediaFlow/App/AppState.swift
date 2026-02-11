import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var selectedNavItem: NavigationItem = .library
    @Published var backendURL: String = "http://localhost:9876"
    @Published var activeJobCount: Int = 0
    @Published var aggregateFPS: Double = 0.0
    @Published var isBackendOnline: Bool = false
    @Published var plexServers: [PlexServerInfo] = []
    @Published var showingTranscodeConfig: Bool = false
    @Published var selectedMediaItems: Set<Int> = []
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var showAddServer: Bool = false

    private var healthCheckTimer: Timer?

    init() {
        startHealthCheck()
    }

    func startHealthCheck() {
        healthCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkBackendHealth()
            }
        }
        Task { await checkBackendHealth() }
    }

    func checkBackendHealth() async {
        do {
            let client = APIClient(baseURL: backendURL)
            let _: HealthResponse = try await client.get("/api/health")
            isBackendOnline = true
        } catch {
            isBackendOnline = false
        }
    }

    func showError(_ message: String) {
        errorMessage = message
        showError = true
    }
}

struct HealthResponse: Codable {
    let status: String
    let service: String
    let version: String
}

struct PlexServerInfo: Identifiable, Codable {
    let id: Int
    let name: String
    let url: String
    var machineId: String?
    var version: String?
    var isActive: Bool = true
    var lastSyncedAt: String?
    var libraryCount: Int = 0
    var sshHostname: String?
    var sshPort: Int? = 22
    var sshUsername: String?
    var sshKeyPath: String?
    var sshPassword: String?
    var benchmarkPath: String?
}
