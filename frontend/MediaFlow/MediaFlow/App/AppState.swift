import SwiftUI
import Combine

struct ToastItem: Identifiable {
    let id = UUID()
    let message: String
    let icon: String
    let style: ToastStyle

    enum ToastStyle {
        case error, warning, success, info

        var color: Color {
            switch self {
            case .error: return .mfError
            case .warning: return .mfWarning
            case .success: return .mfSuccess
            case .info: return .mfPrimary
            }
        }
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var selectedNavItem: NavigationItem = .library
    @Published var backendURL: String = BackendService.defaultBaseURL
    @Published var activeJobCount: Int = 0
    @Published var aggregateFPS: Double = 0.0
    @Published var isBackendOnline: Bool = false
    @Published var plexServers: [PlexServerInfo] = []
    @Published var showingTranscodeConfig: Bool = false
    @Published var selectedMediaItems: Set<Int> = []
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    @Published var showAddServer: Bool = false
    @Published var toasts: [ToastItem] = []
    @Published var hasCompletedOnboarding: Bool = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    @Published var droppedFilePath: String?

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

    func showToast(_ message: String, icon: String = "exclamationmark.triangle.fill", style: ToastItem.ToastStyle = .error, duration: TimeInterval = 12) {
        let toast = ToastItem(message: message, icon: icon, style: style)
        toasts.append(toast)
        Task {
            try? await Task.sleep(for: .seconds(duration))
            toasts.removeAll { $0.id == toast.id }
        }
    }

    func dismissToast(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
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
