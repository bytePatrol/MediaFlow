import Foundation
import Combine

@MainActor
class WebSocketService: ObservableObject {
    @Published var isConnected: Bool = false
    private var client: WebSocketClient?

    func connect(url: String = "ws://localhost:9876/ws") {
        client = WebSocketClient(urlString: url)
        client?.connect()
        isConnected = true
        setupNotificationSubscriptions()
    }

    func disconnect() {
        client?.disconnect()
        isConnected = false
    }

    func subscribe(to event: String, handler: @escaping (WSMessage) -> Void) {
        client?.subscribe(to: event, handler: handler)
    }

    // MARK: - Local Notification Triggers

    private func setupNotificationSubscriptions() {
        client?.subscribe(to: "job.completed") { message in
            let jobId = message.data["job_id"]?.intValue
            let outputSize = message.data["output_size"]?.intValue
            let duration = message.data["duration"]?.doubleValue

            var body = "Job #\(jobId ?? 0) finished"
            if let size = outputSize {
                let sizeMB = Double(size) / (1024 * 1024)
                body += " — \(String(format: "%.1f", sizeMB)) MB"
            }
            if let dur = duration {
                body += " in \(String(format: "%.0f", dur))s"
            }

            NotificationService.shared.showNotification(
                title: "Transcode Complete",
                body: body,
                identifier: "job.completed.\(jobId ?? 0)"
            )
        }

        client?.subscribe(to: "job.failed") { message in
            let jobId = message.data["job_id"]?.intValue
            let error = message.data["error"]?.stringValue ?? "Unknown error"

            NotificationService.shared.showNotification(
                title: "Transcode Failed",
                body: "Job #\(jobId ?? 0): \(error)",
                identifier: "job.failed.\(jobId ?? 0)"
            )
        }

        client?.subscribe(to: "sync.completed") { message in
            let serverName = message.data["server_name"]?.stringValue ?? "Unknown"
            let itemsSynced = message.data["items_synced"]?.intValue ?? 0

            NotificationService.shared.showNotification(
                title: "Library Sync Complete",
                body: "\(serverName) — \(itemsSynced) items synced",
                identifier: "sync.completed.\(serverName)"
            )
        }

        client?.subscribe(to: "analysis.completed") { message in
            let recsCount = message.data["recommendations_generated"]?.intValue ?? 0
            let totalSavings = message.data["total_estimated_savings"]?.intValue ?? 0
            let savingsGB = Double(totalSavings) / 1_000_000_000

            NotificationService.shared.showNotification(
                title: "Analysis Complete",
                body: "\(recsCount) recommendations, \(String(format: "%.1f", savingsGB)) GB potential savings",
                identifier: "analysis.completed"
            )
        }
    }
}
