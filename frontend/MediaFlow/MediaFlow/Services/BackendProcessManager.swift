import Foundation
import AppKit

@MainActor
class BackendProcessManager: ObservableObject {
    static let shared = BackendProcessManager()

    @Published var isRunning = false
    @Published var port: Int = 9876
    @Published var backendURL: String = "http://localhost:9876"
    @Published var startupError: String?
    @Published var state: StartupState = .idle

    enum StartupState {
        case idle
        case starting
        case running
        case failed(String)

        var isReady: Bool {
            if case .running = self { return true }
            return false
        }
    }

    private var process: Process?
    private var isBundledMode: Bool { bundledBinaryURL != nil }

    private var bundledBinaryURL: URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let binaryURL = resourceURL.appendingPathComponent("backend/mediaflow-server")
        return FileManager.default.fileExists(atPath: binaryURL.path) ? binaryURL : nil
    }

    private var dataDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MediaFlow")
    }

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopBackendSync()
            }
        }
    }

    func startBackend() async {
        guard let binaryURL = bundledBinaryURL else {
            // Dev mode: no bundled binary, assume backend is running externally
            state = .running
            isRunning = true
            return
        }

        state = .starting
        startupError = nil

        // Find a free port
        do {
            port = try findFreePort()
        } catch {
            let msg = "Failed to find free port: \(error.localizedDescription)"
            state = .failed(msg)
            startupError = msg
            return
        }

        backendURL = "http://localhost:\(port)"

        // Ensure data directory exists
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)

        // Launch the backend process
        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = [
            "--port", "\(port)",
            "--host", "127.0.0.1",
            "--data-dir", dataDirectory.path,
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            process = proc
        } catch {
            let msg = "Failed to launch backend: \(error.localizedDescription)"
            state = .failed(msg)
            startupError = msg
            return
        }

        // Wait for the health endpoint to respond
        let healthy = await waitForHealth()
        if healthy {
            isRunning = true
            state = .running
            BackendService.defaultBaseURL = backendURL
            APIClient.defaultBaseURL = backendURL
        } else {
            let msg = "Backend failed to start within timeout"
            state = .failed(msg)
            startupError = msg
            stopBackendSync()
        }
    }

    func stopBackend() {
        stopBackendSync()
    }

    func retry() async {
        stopBackendSync()
        await startBackend()
    }

    // MARK: - Private

    private func stopBackendSync() {
        guard let proc = process, proc.isRunning else {
            process = nil
            isRunning = false
            return
        }
        proc.terminate()

        // Give it 3 seconds, then interrupt
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [weak self] in
            if proc.isRunning {
                proc.interrupt()
            }
            DispatchQueue.main.async {
                self?.process = nil
                self?.isRunning = false
            }
        }
    }

    private func waitForHealth() async -> Bool {
        let url = URL(string: "\(backendURL)/api/health")!
        for _ in 0..<30 {
            try? await Task.sleep(for: .milliseconds(500))

            // Check process is still alive
            if let proc = process, !proc.isRunning {
                return false
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) {
                    // Verify it's actually our API
                    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       json["service"] as? String == "MediaFlow API" {
                        return true
                    }
                }
            } catch {
                continue
            }
        }
        return false
    }

    private func findFreePort() throws -> Int {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "BackendProcessManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create socket"])
        }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        addr.sin_port = 0 // Let OS pick

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                Darwin.bind(fd, ptr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw NSError(domain: "BackendProcessManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to bind socket"])
        }

        var resolvedAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &resolvedAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { ptr in
                getsockname(fd, ptr, &len)
            }
        }
        guard nameResult == 0 else {
            throw NSError(domain: "BackendProcessManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to get socket name"])
        }

        return Int(resolvedAddr.sin_port.bigEndian)
    }
}
