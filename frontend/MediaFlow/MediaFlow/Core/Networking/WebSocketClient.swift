import Foundation
import Combine

struct WSMessage: Codable {
    let event: String
    let timestamp: String
    let data: [String: AnyCodable]
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) { value = intVal }
        else if let doubleVal = try? container.decode(Double.self) { value = doubleVal }
        else if let stringVal = try? container.decode(String.self) { value = stringVal }
        else if let boolVal = try? container.decode(Bool.self) { value = boolVal }
        else if let dictVal = try? container.decode([String: AnyCodable].self) { value = dictVal }
        else if let arrVal = try? container.decode([AnyCodable].self) { value = arrVal }
        else if container.decodeNil() { value = NSNull() }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type") }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let v as Int: try container.encode(v)
        case let v as Double: try container.encode(v)
        case let v as String: try container.encode(v)
        case let v as Bool: try container.encode(v)
        case let v as [String: AnyCodable]: try container.encode(v)
        case let v as [AnyCodable]: try container.encode(v)
        case is NSNull: try container.encodeNil()
        default: try container.encodeNil()
        }
    }

    var intValue: Int? {
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        return nil
    }
    var doubleValue: Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        return nil
    }
    var stringValue: String? { value as? String }
    var boolValue: Bool? { value as? Bool }
}

@MainActor
class WebSocketClient: ObservableObject {
    @Published var isConnected: Bool = false

    private var webSocketTask: URLSessionWebSocketTask?
    private let url: URL
    private var reconnectDelay: TimeInterval = 1.0
    private var maxReconnectDelay: TimeInterval = 30.0
    private var eventHandlers: [String: [(WSMessage) -> Void]] = [:]

    init(url: URL) {
        self.url = url
    }

    convenience init(urlString: String = "ws://localhost:9876/ws") {
        self.init(url: URL(string: urlString)!)
    }

    func connect() {
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        isConnected = true
        reconnectDelay = 1.0
        receiveMessage()
        sendPing()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isConnected = false
    }

    func subscribe(to event: String, handler: @escaping (WSMessage) -> Void) {
        if eventHandlers[event] == nil {
            eventHandlers[event] = []
        }
        eventHandlers[event]?.append(handler)
    }

    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleMessage(text)
                        }
                    @unknown default: break
                    }
                    self.receiveMessage()
                case .failure:
                    self.isConnected = false
                    self.reconnect()
                }
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let message = try? JSONDecoder().decode(WSMessage.self, from: data) else {
            return
        }

        // Call specific event handlers
        eventHandlers[message.event]?.forEach { $0(message) }
        // Call wildcard handlers
        eventHandlers["*"]?.forEach { $0(message) }
        // Call category handlers (e.g., "job.*")
        let category = message.event.split(separator: ".").first.map(String.init) ?? ""
        eventHandlers["\(category).*"]?.forEach { $0(message) }
    }

    private func sendPing() {
        Task {
            try? await Task.sleep(for: .seconds(30))
            guard isConnected else { return }
            webSocketTask?.sendPing { [weak self] error in
                if error != nil {
                    Task { @MainActor [weak self] in
                        self?.isConnected = false
                        self?.reconnect()
                    }
                } else {
                    Task { @MainActor [weak self] in
                        self?.sendPing()
                    }
                }
            }
        }
    }

    private func reconnect() {
        Task {
            try? await Task.sleep(for: .seconds(reconnectDelay))
            reconnectDelay = min(reconnectDelay * 2, maxReconnectDelay)
            connect()
        }
    }
}
