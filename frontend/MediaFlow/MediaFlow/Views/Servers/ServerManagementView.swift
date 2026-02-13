import SwiftUI

struct ServerManagementView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ServerManagementViewModel()
    @State private var addPanel = AddServerPanel()
    @State private var editPanel = EditServerPanel()
    @State private var cloudDeployPanel = CloudDeployPanel()
    @State private var showComparison = false
    @State private var showDestroyedCloud = false
    @State private var serverToDelete: WorkerServer?
    @State private var showDeleteConfirm = false
    @State private var serverToTeardown: WorkerServer?
    @State private var showTeardownConfirm = false

    private var activeServers: [WorkerServer] {
        viewModel.servers.filter { server in
            guard server.isCloud else { return true }
            let alive = ["creating", "bootstrapping", "active"]
            return alive.contains(server.cloudStatus ?? "")
        }
    }

    private var destroyedCloudServers: [WorkerServer] {
        viewModel.servers.filter { server in
            guard server.isCloud else { return false }
            let alive = ["creating", "bootstrapping", "active"]
            return !alive.contains(server.cloudStatus ?? "")
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Server Management")
                            .font(.mfTitle)
                        Text("Real-time transcoding infrastructure & storage optimization analytics.")
                            .font(.mfBody)
                            .foregroundColor(.mfTextSecondary)
                    }
                    Spacer()

                    HStack(spacing: 10) {
                        Button {
                            showComparison = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chart.bar.xaxis")
                                Text("Compare")
                            }
                            .secondaryButton()
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await viewModel.triggerBenchmarkAll() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "speedometer")
                                Text("Benchmark All")
                            }
                            .secondaryButton()
                        }
                        .buttonStyle(.plain)

                        Button {
                            cloudDeployPanel.show {
                                Task { await viewModel.loadServers() }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "cloud.bolt")
                                Text("Deploy Cloud GPU")
                            }
                            .primaryButton()
                        }
                        .buttonStyle(.plain)

                        Button {
                            addPanel.show {
                                Task { await viewModel.loadServers() }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Add Server Node")
                            }
                            .secondaryButton()
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Server Grid
                HStack(alignment: .top, spacing: 4) {
                    Text("Connected Nodes")
                        .font(.mfHeadline)
                    Image(systemName: "server.rack")
                        .foregroundColor(.mfPrimary)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 500))], spacing: 16) {
                    ForEach(activeServers) { server in
                        serverCard(for: server)
                    }

                    // Add New Placeholder
                    Button {
                        addPanel.show {
                            Task { await viewModel.loadServers() }
                        }
                    } label: {
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.mfPrimary.opacity(0.05))
                                    .frame(width: 56, height: 56)
                                Image(systemName: "plus")
                                    .font(.system(size: 22))
                                    .foregroundColor(.mfPrimary)
                            }
                            Text("Connect New Server")
                                .font(.system(size: 14, weight: .bold))
                            Text("Add hardware accelerators or cloud nodes.")
                                .font(.mfCaption)
                                .foregroundColor(.mfTextMuted)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 240)
                        .contentShape(Rectangle())
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.mfPrimary.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Destroyed Cloud Instances (collapsed by default)
                if !destroyedCloudServers.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showDestroyedCloud.toggle()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: showDestroyedCloud ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.mfTextMuted)
                            Text("Destroyed Cloud Instances")
                                .font(.mfBodyMedium)
                                .foregroundColor(.mfTextSecondary)
                            Text("\(destroyedCloudServers.count)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.mfTextMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.mfSurfaceLight)
                                .clipShape(Capsule())
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)

                    if showDestroyedCloud {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 500))], spacing: 16) {
                            ForEach(destroyedCloudServers) { server in
                                serverCard(for: server)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color.mfBackground)
        .task {
            viewModel.onCloudDeployFailed = { [weak appState] errorMsg in
                appState?.showToast("Cloud GPU deploy failed: \(errorMsg)", icon: "cloud.bolt", style: .error)
            }
            viewModel.onCloudAutoDeployTriggered = { [weak appState] jobCount, region in
                appState?.showToast("Auto-deploying cloud GPU for \(jobCount) queued job\(jobCount == 1 ? "" : "s")...", icon: "cloud.bolt.fill", style: .info)
            }
            await viewModel.loadServers()
            await viewModel.loadBenchmarks()
            viewModel.connectWebSocket()
        }
        .onDisappear {
            viewModel.disconnectWebSocket()
        }
        .confirmationDialog("Delete server?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let server = serverToDelete {
                    Task { await viewModel.deleteServer(server) }
                }
            }
        } message: {
            Text("Remove \"\(serverToDelete?.name ?? "")\" from MediaFlow? This cannot be undone.")
        }
        .confirmationDialog("Tear down cloud instance?", isPresented: $showTeardownConfirm) {
            Button("Tear Down", role: .destructive) {
                if let server = serverToTeardown {
                    Task { await viewModel.teardownCloudServer(server) }
                }
            }
        } message: {
            Text("Destroy the cloud GPU instance \"\(serverToTeardown?.name ?? "")\"? The instance will be terminated and all data on it will be lost.")
        }
        .sheet(isPresented: $showComparison) {
            ServerComparisonView(servers: viewModel.servers, metrics: viewModel.serverMetrics, benchmarks: viewModel.benchmarkResults)
                .frame(minWidth: 800, minHeight: 500)
        }
    }

    @ViewBuilder
    private func serverCard(for server: WorkerServer) -> some View {
        ServerCardView(
            server: server,
            metrics: viewModel.serverMetrics[server.id],
            benchmark: viewModel.benchmarkResults[server.id],
            isBenchmarking: viewModel.benchmarkInProgress.contains(server.id),
            benchmarkCompleted: viewModel.benchmarkJustCompleted.contains(server.id),
            benchmarkError: viewModel.benchmarkError[server.id],
            isProvisioning: viewModel.provisionInProgress.contains(server.id),
            provisionStep: viewModel.provisionSteps[server.id],
            provisionCompleted: viewModel.provisionCompleted.contains(server.id),
            provisionError: viewModel.provisionError[server.id],
            cloudDeployProgress: viewModel.cloudDeployProgress[server.id],
            cloudDeployError: viewModel.cloudDeployError[server.id],
            onEdit: {
                editPanel.show(
                    server: server,
                    onSave: { request in
                        Task { await viewModel.updateServer(server.id, request: request) }
                    },
                    onDelete: {
                        serverToDelete = server
                        showDeleteConfirm = true
                    }
                )
            },
            onBenchmark: {
                Task { await viewModel.triggerBenchmark(for: server) }
            },
            onProvision: {
                Task { await viewModel.triggerProvision(for: server) }
            },
            onTeardown: {
                serverToTeardown = server
                showTeardownConfirm = true
            }
        )
    }
}
