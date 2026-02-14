import SwiftUI

struct LogsView: View {
    @StateObject private var viewModel = LogsViewModel()
    @State private var selectedTab: LogsTab = .live

    enum LogsTab: String, CaseIterable {
        case live = "Live Logs"
        case diagnostics = "Diagnostics"

        var icon: String {
            switch self {
            case .live: return "text.alignleft"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(.mfPrimary)
                    Text("Logs & Diagnostics")
                        .font(.mfHeadline)
                }

                Divider().frame(height: 30)

                // Log count
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOG ENTRIES")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                        .tracking(1)
                    Text("\(viewModel.totalLogs)")
                        .font(.mfMonoLarge)
                        .foregroundColor(.mfPrimary)
                }

                Spacer()

                HStack(spacing: 8) {
                    // Auto-refresh toggle
                    Button {
                        viewModel.toggleAutoRefresh()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.isAutoRefresh ? "pause.circle" : "play.circle")
                                .font(.system(size: 11))
                            Text(viewModel.isAutoRefresh ? "Pause" : "Live")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(viewModel.isAutoRefresh ? .mfSuccess : .mfTextSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(viewModel.isAutoRefresh ? Color.mfSuccess.opacity(0.1) : Color.mfSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(viewModel.isAutoRefresh ? Color.mfSuccess.opacity(0.3) : Color.mfGlassBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // Refresh
                    Button {
                        Task {
                            await viewModel.loadLogs()
                            await viewModel.loadDiagnostics()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text("Refresh")
                        }
                        .secondaryButton()
                    }
                    .buttonStyle(.plain)

                    // Export
                    Button {
                        if let url = viewModel.exportLogsURL() {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                            Text("Export")
                        }
                        .secondaryButton()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(Color.mfSurface)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .bottom)

            // Tab bar + content
            HSplitView {
                // Sidebar
                VStack(alignment: .leading, spacing: 8) {
                    Text("VIEW")
                        .mfSectionHeader()
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    ForEach(LogsTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 16))
                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                                Spacer()
                            }
                            .foregroundColor(selectedTab == tab ? .mfPrimary : .mfTextSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? Color.mfPrimary.opacity(0.1) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().padding(.vertical, 8)

                    // Level filter (only for Live tab)
                    if selectedTab == .live {
                        Text("LEVEL")
                            .mfSectionHeader()
                            .padding(.horizontal, 12)

                        ForEach(viewModel.levels, id: \.self) { level in
                            Button {
                                viewModel.selectedLevel = level
                                Task { await viewModel.loadLogs() }
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(colorForLevel(level))
                                        .frame(width: 6, height: 6)
                                    Text(level)
                                        .font(.system(size: 12, weight: viewModel.selectedLevel == level ? .semibold : .regular))
                                    Spacer()
                                }
                                .foregroundColor(viewModel.selectedLevel == level ? .mfPrimary : .mfTextSecondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(viewModel.selectedLevel == level ? Color.mfPrimary.opacity(0.1) : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()
                }
                .frame(minWidth: 160, idealWidth: 200, maxWidth: 240)
                .background(Color.mfSurface)

                // Main content
                Group {
                    switch selectedTab {
                    case .live:
                        liveLogsContent
                    case .diagnostics:
                        diagnosticsContent
                    }
                }
            }
        }
        .background(Color.mfBackground)
        .task {
            await viewModel.loadLogs()
            await viewModel.loadDiagnostics()
        }
    }

    // MARK: - Live Logs

    private var liveLogsContent: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.mfTextMuted)
                TextField("Filter logs...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit {
                        Task { await viewModel.loadLogs() }
                    }
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                        Task { await viewModel.loadLogs() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.mfTextMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.mfSurface)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .bottom)

            // Log table
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.logs.enumerated()), id: \.offset) { index, entry in
                            LogRowView(entry: entry)
                                .id(index)
                        }

                        if viewModel.logs.isEmpty && !viewModel.isLoading {
                            EmptyStateView(
                                icon: "doc.text",
                                title: "No log entries",
                                description: "Log entries will appear here as the backend processes requests."
                            )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Diagnostics

    private var diagnosticsContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let diag = viewModel.diagnostics {
                    // System Info
                    DiagnosticSection(title: "SYSTEM") {
                        DiagnosticRow(label: "Platform", value: diag.system.platform)
                        DiagnosticRow(label: "Architecture", value: diag.system.architecture)
                        DiagnosticRow(label: "Hostname", value: diag.system.hostname)
                        DiagnosticRow(label: "Python", value: String(diag.system.pythonVersion.prefix(30)))
                    }

                    // App Info
                    DiagnosticSection(title: "APPLICATION") {
                        DiagnosticRow(label: "Version", value: diag.app.version)
                        DiagnosticRow(label: "Process ID", value: "\(diag.app.pid)")
                        DiagnosticRow(label: "Database Size", value: viewModel.formatBytes(diag.app.dbSizeBytes))
                        DiagnosticRow(label: "Log Buffer", value: "\(diag.app.logBufferSize) / \(diag.app.logBufferCapacity)")
                    }

                    // Cache Info
                    DiagnosticSection(title: "TRANSCODE CACHE") {
                        DiagnosticRow(label: "Directory", value: diag.app.cacheDir)
                        DiagnosticRow(label: "Files", value: "\(diag.app.cacheFiles)")
                        DiagnosticRow(label: "Size", value: viewModel.formatBytes(diag.app.cacheSizeBytes))
                    }
                } else {
                    ProgressView()
                        .padding(.top, 80)
                }
            }
            .padding(20)
        }
    }

    private func colorForLevel(_ level: String) -> Color {
        switch level {
        case "ERROR": return .mfError
        case "WARNING": return .orange
        case "DEBUG": return .mfTextMuted
        case "INFO": return .mfSuccess
        default: return .mfPrimary
        }
    }
}

// MARK: - Log Row

struct LogRowView: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(formatTime(entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.mfTextMuted)
                .frame(width: 80, alignment: .leading)

            // Level badge
            Text(entry.level)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(entry.levelColor)
                .frame(width: 55, alignment: .leading)

            // Logger name
            Text(entry.logger)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.mfPrimary.opacity(0.7))
                .frame(width: 120, alignment: .leading)
                .lineLimit(1)

            // Message
            Text(entry.message)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.mfTextSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(
            entry.level == "ERROR" || entry.level == "CRITICAL"
            ? Color.mfError.opacity(0.04)
            : entry.level == "WARNING"
            ? Color.orange.opacity(0.03)
            : Color.clear
        )
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder.opacity(0.3)),
            alignment: .bottom
        )
    }

    private func formatTime(_ iso: String) -> String {
        // Extract just HH:MM:SS from ISO timestamp
        if let tIndex = iso.firstIndex(of: "T") {
            let timeStr = String(iso[iso.index(after: tIndex)...])
            return String(timeStr.prefix(8))
        }
        return String(iso.suffix(8))
    }
}

// MARK: - Diagnostic Components

struct DiagnosticSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.mfTextMuted)
                .tracking(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            VStack(spacing: 0) {
                content
            }
            .background(Color.mfSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.mfGlassBorder, lineWidth: 1)
            )
        }
    }
}

struct DiagnosticRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.mfTextSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.mfTextPrimary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder.opacity(0.3)),
            alignment: .bottom
        )
    }
}
