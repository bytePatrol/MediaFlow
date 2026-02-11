import SwiftUI

struct ServerManagementView: View {
    @StateObject private var viewModel = ServerManagementViewModel()
    @State private var addPanel = AddServerPanel()
    @State private var editPanel = EditServerPanel()
    @State private var showComparison = false

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
                            addPanel.show {
                                Task { await viewModel.loadServers() }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                Text("Add Server Node")
                            }
                            .primaryButton()
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
                    ForEach(viewModel.servers) { server in
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
                            onEdit: {
                                editPanel.show(
                                    server: server,
                                    onSave: { request in
                                        Task { await viewModel.updateServer(server.id, request: request) }
                                    },
                                    onDelete: {
                                        Task { await viewModel.deleteServer(server) }
                                    }
                                )
                            },
                            onBenchmark: {
                                Task { await viewModel.triggerBenchmark(for: server) }
                            },
                            onProvision: {
                                Task { await viewModel.triggerProvision(for: server) }
                            }
                        )
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
            }
            .padding(24)
        }
        .background(Color.mfBackground)
        .task {
            await viewModel.loadServers()
            await viewModel.loadBenchmarks()
            viewModel.connectWebSocket()
        }
        .onDisappear {
            viewModel.disconnectWebSocket()
        }
        .sheet(isPresented: $showComparison) {
            ServerComparisonView(servers: viewModel.servers, metrics: viewModel.serverMetrics, benchmarks: viewModel.benchmarkResults)
                .frame(minWidth: 800, minHeight: 500)
        }
    }
}
