import SwiftUI
import Combine

struct LogEntry: Identifiable, Codable {
    let timestamp: String
    let level: String
    let logger: String
    let message: String

    var id: String { "\(timestamp)-\(message.prefix(40))" }

    var levelColor: Color {
        switch level {
        case "ERROR", "CRITICAL": return .mfError
        case "WARNING": return .orange
        case "DEBUG": return .mfTextMuted
        default: return .mfTextSecondary
        }
    }
}

struct LogsResponse: Codable {
    let items: [LogEntry]
    let total: Int
}

struct DiagnosticsResponse: Codable {
    let system: SystemInfo
    let app: AppInfo

    struct SystemInfo: Codable {
        let platform: String
        let pythonVersion: String
        let architecture: String
        let hostname: String
    }

    struct AppInfo: Codable {
        let version: String
        let pid: Int
        let dbSizeBytes: Int
        let cacheDir: String
        let cacheSizeBytes: Int
        let cacheFiles: Int
        let logBufferSize: Int
        let logBufferCapacity: Int
    }
}

@MainActor
class LogsViewModel: ObservableObject {
    @Published var logs: [LogEntry] = []
    @Published var diagnostics: DiagnosticsResponse?
    @Published var isLoading = false
    @Published var isAutoRefresh = false
    @Published var selectedLevel: String = "ALL"
    @Published var searchText: String = ""
    @Published var totalLogs: Int = 0

    private let service = BackendService()
    private var refreshTimer: Timer?

    let levels = ["ALL", "DEBUG", "INFO", "WARNING", "ERROR"]

    func loadLogs() async {
        isLoading = true
        do {
            let client = APIClient(baseURL: service.client.baseURL)
            var query = "/api/logs?limit=500"
            if selectedLevel != "ALL" {
                query += "&level=\(selectedLevel)"
            }
            let response: LogsResponse = try await client.get(query)
            var entries = response.items
            if !searchText.isEmpty {
                let term = searchText.lowercased()
                entries = entries.filter {
                    $0.message.lowercased().contains(term) ||
                    $0.logger.lowercased().contains(term)
                }
            }
            logs = entries
            totalLogs = response.total
        } catch {
            print("Failed to load logs: \(error)")
        }
        isLoading = false
    }

    func loadDiagnostics() async {
        do {
            let client = APIClient(baseURL: service.client.baseURL)
            diagnostics = try await client.get("/api/logs/diagnostics")
        } catch {
            print("Failed to load diagnostics: \(error)")
        }
    }

    func toggleAutoRefresh() {
        isAutoRefresh.toggle()
        if isAutoRefresh {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.loadLogs()
                }
            }
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }

    func exportLogsURL() -> URL? {
        // Return URL for the export endpoint so the user can save it
        URL(string: "\(service.client.baseURL)/api/logs/export")
    }

    func formatBytes(_ bytes: Int) -> String {
        if bytes >= 1_073_741_824 {
            return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
        } else if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576)
        } else if bytes >= 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
        return "\(bytes) B"
    }

    deinit {
        refreshTimer?.invalidate()
    }
}
