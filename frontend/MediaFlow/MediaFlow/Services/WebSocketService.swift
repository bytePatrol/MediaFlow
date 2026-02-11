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
    }

    func disconnect() {
        client?.disconnect()
        isConnected = false
    }

    func subscribe(to event: String, handler: @escaping (WSMessage) -> Void) {
        client?.subscribe(to: event, handler: handler)
    }
}
