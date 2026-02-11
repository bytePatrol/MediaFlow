import SwiftUI
import Foundation

@MainActor
class ServerManagementViewModel: ObservableObject {
    @Published var servers: [WorkerServer] = []
    @Published var isLoading: Bool = false
    @Published var showAddServer: Bool = false
    @Published var serverMetrics: [Int: ServerStatus] = [:]
    @Published var benchmarkResults: [Int: BenchmarkResult] = [:]
    @Published var benchmarkInProgress: Set<Int> = []
    @Published var benchmarkJustCompleted: Set<Int> = []
    @Published var benchmarkError: [Int: String] = [:]
    @Published var provisionInProgress: Set<Int> = []
    @Published var provisionSteps: [Int: ProvisionProgress] = [:]
    @Published var provisionCompleted: Set<Int> = []
    @Published var provisionError: [Int: String] = [:]

    private let service: BackendService
    private var wsClient: WebSocketClient?
    private var benchmarkStartTimes: [Int: Date] = [:]

    init(service: BackendService = BackendService()) {
        self.service = service
    }

    func loadServers() async {
        isLoading = true
        do {
            servers = try await service.getWorkerServers()
            for server in servers where server.status == "online" || server.isLocal {
                if let status = try? await service.getServerStatus(id: server.id) {
                    serverMetrics[server.id] = status
                }
            }
        } catch {
            print("Failed to load servers: \(error)")
        }
        isLoading = false
    }

    func loadBenchmarks() async {
        for server in servers {
            do {
                let benchmarks = try await service.getBenchmarks(serverId: server.id)
                if let latest = benchmarks.first {
                    benchmarkResults[server.id] = latest
                }
            } catch {
                // Server may not have benchmarks yet
            }
        }
    }

    func triggerBenchmark(for server: WorkerServer) async {
        benchmarkInProgress.insert(server.id)
        benchmarkJustCompleted.remove(server.id)
        benchmarkStartTimes[server.id] = Date()
        do {
            _ = try await service.triggerBenchmark(serverId: server.id)
        } catch {
            benchmarkInProgress.remove(server.id)
            benchmarkStartTimes.removeValue(forKey: server.id)
        }
    }

    func triggerBenchmarkAll() async {
        for server in servers where server.status == "online" || server.isLocal {
            await triggerBenchmark(for: server)
        }
    }

    func triggerProvision(for server: WorkerServer, installGpu: Bool = false) async {
        provisionInProgress.insert(server.id)
        provisionCompleted.remove(server.id)
        provisionError.removeValue(forKey: server.id)
        do {
            _ = try await service.provisionServer(id: server.id, installGpu: installGpu)
        } catch {
            provisionInProgress.remove(server.id)
            provisionError[server.id] = error.localizedDescription
            Task {
                try? await Task.sleep(for: .seconds(8))
                provisionError.removeValue(forKey: server.id)
            }
        }
    }

    func deleteServer(_ server: WorkerServer) async {
        do {
            try await service.deleteWorkerServer(id: server.id)
            servers.removeAll { $0.id == server.id }
            serverMetrics.removeValue(forKey: server.id)
            benchmarkResults.removeValue(forKey: server.id)
        } catch {
            print("Failed to delete server: \(error)")
        }
    }

    func updateServer(_ id: Int, request: UpdateWorkerServerRequest) async {
        do {
            let updated = try await service.updateWorkerServer(id: id, request: request)
            if let idx = servers.firstIndex(where: { $0.id == id }) {
                servers[idx] = updated
            }
        } catch {
            print("Failed to update server: \(error)")
        }
    }

    // MARK: - Benchmark completion with minimum visible duration

    private func finishBenchmark(serverId: Int, result: BenchmarkResult, performanceScore: Double?) {
        let minDuration: TimeInterval = 1.5
        let startTime = benchmarkStartTimes[serverId] ?? Date.distantPast
        let elapsed = Date().timeIntervalSince(startTime)
        let remaining = max(0, minDuration - elapsed)

        Task {
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }
            benchmarkInProgress.remove(serverId)
            benchmarkResults[serverId] = result
            if let idx = servers.firstIndex(where: { $0.id == serverId }) {
                servers[idx].performanceScore = performanceScore
            }
            benchmarkStartTimes.removeValue(forKey: serverId)

            // Show completion state briefly
            benchmarkJustCompleted.insert(serverId)
            try? await Task.sleep(for: .seconds(2.5))
            benchmarkJustCompleted.remove(serverId)
        }
    }

    // MARK: - WebSocket

    func connectWebSocket() {
        guard wsClient == nil else { return }
        let client = WebSocketClient()
        self.wsClient = client
        client.connect()

        client.subscribe(to: "server.metrics") { [weak self] message in
            guard let self = self,
                  let serverId = message.data["server_id"]?.intValue else { return }
            let status = ServerStatus(
                id: serverId,
                name: self.servers.first(where: { $0.id == serverId })?.name ?? "",
                status: message.data["status"]?.stringValue ?? "online",
                cpuPercent: message.data["cpu_percent"]?.doubleValue,
                gpuPercent: message.data["gpu_percent"]?.doubleValue,
                ramUsedGb: message.data["ram_used_gb"]?.doubleValue,
                ramTotalGb: message.data["ram_total_gb"]?.doubleValue,
                gpuTemp: message.data["gpu_temp"]?.doubleValue,
                fanSpeed: message.data["fan_speed"]?.intValue,
                activeJobs: self.serverMetrics[serverId]?.activeJobs ?? 0,
                queuedJobs: self.serverMetrics[serverId]?.queuedJobs ?? 0
            )
            self.serverMetrics[serverId] = status
        }

        client.subscribe(to: "benchmark.completed") { [weak self] message in
            guard let self = self,
                  let serverId = message.data["server_id"]?.intValue else { return }
            let result = BenchmarkResult(
                id: message.data["benchmark_id"]?.intValue ?? 0,
                workerServerId: serverId,
                uploadMbps: message.data["upload_mbps"]?.doubleValue,
                downloadMbps: message.data["download_mbps"]?.doubleValue,
                latencyMs: message.data["latency_ms"]?.doubleValue,
                status: "completed"
            )
            self.finishBenchmark(
                serverId: serverId,
                result: result,
                performanceScore: message.data["performance_score"]?.doubleValue
            )
        }

        client.subscribe(to: "benchmark.failed") { [weak self] message in
            guard let self = self,
                  let serverId = message.data["server_id"]?.intValue else { return }
            self.benchmarkInProgress.remove(serverId)
            self.benchmarkStartTimes.removeValue(forKey: serverId)
            let errorMsg = message.data["error"]?.stringValue ?? "Benchmark failed"
            self.benchmarkError[serverId] = errorMsg
            Task {
                try? await Task.sleep(for: .seconds(4))
                self.benchmarkError.removeValue(forKey: serverId)
            }
        }

        client.subscribe(to: "server.auto_disabled") { [weak self] message in
            guard let self = self,
                  let serverId = message.data["server_id"]?.intValue else { return }
            if let idx = self.servers.firstIndex(where: { $0.id == serverId }) {
                self.servers[idx].isEnabled = false
                self.servers[idx].status = "offline"
            }
        }

        client.subscribe(to: "server.status") { [weak self] message in
            guard let self = self,
                  let serverId = message.data["server_id"]?.intValue,
                  let status = message.data["status"]?.stringValue else { return }
            if let idx = self.servers.firstIndex(where: { $0.id == serverId }) {
                self.servers[idx].status = status
            }
        }

        client.subscribe(to: "provision.progress") { [weak self] message in
            guard let self = self,
                  let serverId = message.data["server_id"]?.intValue else { return }
            let step = ProvisionProgress(
                serverId: serverId,
                progress: message.data["progress"]?.intValue ?? 0,
                step: message.data["step"]?.stringValue ?? "",
                message: message.data["message"]?.stringValue ?? ""
            )
            self.provisionSteps[serverId] = step
        }

        client.subscribe(to: "provision.completed") { [weak self] message in
            guard let self = self,
                  let serverId = message.data["server_id"]?.intValue else { return }
            self.provisionInProgress.remove(serverId)
            self.provisionSteps.removeValue(forKey: serverId)
            self.provisionCompleted.insert(serverId)
            // Reload server data to get updated capabilities
            Task {
                await self.loadServers()
                try? await Task.sleep(for: .seconds(5))
                self.provisionCompleted.remove(serverId)
            }
        }

        client.subscribe(to: "provision.failed") { [weak self] message in
            guard let self = self,
                  let serverId = message.data["server_id"]?.intValue else { return }
            self.provisionInProgress.remove(serverId)
            self.provisionSteps.removeValue(forKey: serverId)
            let errorMsg = message.data["error"]?.stringValue ?? "Provisioning failed"
            self.provisionError[serverId] = errorMsg
            Task {
                try? await Task.sleep(for: .seconds(8))
                self.provisionError.removeValue(forKey: serverId)
            }
        }
    }

    func disconnectWebSocket() {
        wsClient?.disconnect()
        wsClient = nil
    }
}
