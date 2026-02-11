import SwiftUI
import AppKit

enum PlexAuthState: Equatable {
    case idle
    case creatingPin
    case waitingForAuth
    case success(serversDiscovered: Int)
    case expired
    case error(String)
}

@MainActor
class PlexAuthViewModel: ObservableObject {
    @Published var authState: PlexAuthState = .idle

    private var pollingTask: Task<Void, Never>?
    private var currentPinId: Int?
    private let backend = BackendService()

    func startOAuthFlow() {
        authState = .creatingPin
        pollingTask?.cancel()

        pollingTask = Task {
            do {
                let pinResponse = try await backend.createPlexPin()
                currentPinId = pinResponse.pinId

                // Open browser for user authorization
                if let url = URL(string: pinResponse.authUrl) {
                    NSWorkspace.shared.open(url)
                }

                authState = .waitingForAuth

                // Poll every 2s for up to 5 minutes (150 attempts)
                for _ in 0..<150 {
                    if Task.isCancelled { return }
                    try await Task.sleep(for: .seconds(2))
                    if Task.isCancelled { return }

                    let status = try await backend.checkPlexPinStatus(pinId: pinResponse.pinId)

                    switch status.status {
                    case "authenticated":
                        authState = .success(serversDiscovered: status.serversDiscovered ?? 0)
                        return
                    case "expired":
                        authState = .expired
                        return
                    case "error":
                        authState = .error(status.errorMessage ?? "Unknown error")
                        return
                    default:
                        continue // still pending
                    }
                }

                // Timed out after 5 minutes
                authState = .expired
            } catch {
                if !Task.isCancelled {
                    authState = .error(error.localizedDescription)
                }
            }
        }
    }

    func cancelAuth() {
        pollingTask?.cancel()
        pollingTask = nil
        currentPinId = nil
        authState = .idle
    }
}
