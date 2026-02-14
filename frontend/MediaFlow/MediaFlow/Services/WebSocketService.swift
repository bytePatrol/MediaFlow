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
        // Unified push handler: backend formats title/body and sends via notification.push
        client?.subscribe(to: "notification.push") { message in
            let title = message.data["title"]?.stringValue ?? "MediaFlow"
            let body = message.data["body"]?.stringValue ?? ""
            let event = message.data["event"]?.stringValue ?? "unknown"

            NotificationService.shared.showNotification(
                title: title,
                body: body,
                identifier: "\(event).\(UUID().uuidString.prefix(8))"
            )
        }
    }
}
