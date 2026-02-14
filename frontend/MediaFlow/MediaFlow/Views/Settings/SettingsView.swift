import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case storage = "Storage"
        case scheduling = "Scheduling"
        case intelligence = "Intelligence"
        case cloudGpu = "Cloud GPU"
        case notifications = "Notifications"
        case api = "API"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.mfTitle)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding(24)

            // Tab Bar
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .medium))
                            .foregroundColor(selectedTab == tab ? .mfPrimary : .mfTextSecondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(selectedTab == tab ? Color.mfPrimary.opacity(0.1) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 24)

            Divider()
                .background(Color.mfGlassBorder)
                .padding(.top, 12)

            // Content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView()
                    case .storage:
                        StorageSettingsView()
                    case .scheduling:
                        SchedulingSettingsView()
                    case .intelligence:
                        IntelligenceSettingsView()
                    case .cloudGpu:
                        CloudGPUSettingsView()
                    case .notifications:
                        NotificationSettingsView()
                    case .api:
                        APISettingsView()
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: selectedTab)
            }
            .padding(24)
        }
        .background(Color.mfBackground)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var plexAuth = PlexAuthViewModel()
    @State private var plexURL: String = ""
    @State private var plexToken: String = ""
    @State private var backendURL: String = "http://localhost:9876"
    @State private var isConnecting: Bool = false
    @State private var connectionStatus: String = ""
    @State private var showManualConnection: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Backend Connection
            VStack(alignment: .leading, spacing: 12) {
                Text("BACKEND CONNECTION")
                    .mfSectionHeader()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Backend URL")
                        .font(.mfCaption)
                        .foregroundColor(.mfTextSecondary)
                    HStack {
                        TextField("http://localhost:9876", text: $backendURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 400)

                        Circle()
                            .fill(appState.isBackendOnline ? Color.mfSuccess : Color.mfError)
                            .frame(width: 10, height: 10)
                        Text(appState.isBackendOnline ? "Connected" : "Offline")
                            .font(.mfCaption)
                            .foregroundColor(appState.isBackendOnline ? .mfSuccess : .mfError)
                    }
                }
            }
            .padding(20)
            .cardStyle()

            // Plex Account
            VStack(alignment: .leading, spacing: 12) {
                Text("PLEX ACCOUNT")
                    .mfSectionHeader()

                // Sign in with Plex button + state UI
                plexOAuthSection

                // Manual connection as collapsible fallback
                DisclosureGroup("Manual Connection (Advanced)", isExpanded: $showManualConnection) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Plex Server URL")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextSecondary)
                        TextField("https://your-plex-server:32400", text: $plexURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 400)

                        Text("Plex Token")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextSecondary)
                        SecureField("Enter your Plex token", text: $plexToken)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 400)

                        HStack {
                            Button {
                                Task { await connectPlex() }
                            } label: {
                                HStack(spacing: 6) {
                                    if isConnecting {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "link")
                                    }
                                    Text(isConnecting ? "Connecting..." : "Connect to Plex")
                                }
                                .primaryButton()
                            }
                            .buttonStyle(.plain)
                            .disabled(isConnecting || plexURL.isEmpty || plexToken.isEmpty)

                            if !connectionStatus.isEmpty {
                                Text(connectionStatus)
                                    .font(.mfCaption)
                                    .foregroundColor(connectionStatus.contains("Success") ? .mfSuccess : .mfError)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.mfBody)
                .foregroundColor(.mfTextSecondary)
            }
            .padding(20)
            .cardStyle()

            // Connected Servers List
            if !appState.plexServers.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("CONNECTED SERVERS")
                        .mfSectionHeader()

                    ForEach(Array(appState.plexServers.enumerated()), id: \.element.id) { index, server in
                        PlexServerRow(server: server, index: index)
                    }
                }
                .padding(20)
                .cardStyle()
            }

            Spacer()
        }
        .onAppear {
            if appState.plexServers.isEmpty {
                Task { await refreshServers() }
            }
        }
        .onChange(of: plexAuth.authState) { _, newState in
            if case .success = newState {
                Task { await refreshServers() }
            }
        }
    }

    @ViewBuilder
    private var plexOAuthSection: some View {
        switch plexAuth.authState {
        case .idle:
            Button {
                plexAuth.startOAuthFlow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.key")
                    Text("Sign in with Plex")
                }
                .primaryButton()
            }
            .buttonStyle(.plain)

        case .creatingPin:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
                Text("Setting up authentication...")
                    .font(.mfCaption)
                    .foregroundColor(.mfTextSecondary)
            }

        case .waitingForAuth:
            HStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
                Text("Waiting for authorization in browser...")
                    .font(.mfCaption)
                    .foregroundColor(.mfTextSecondary)

                Button("Cancel") {
                    plexAuth.cancelAuth()
                }
                .font(.mfCaption)
                .foregroundColor(.mfError)
                .buttonStyle(.plain)
            }

        case .success(let count):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.mfSuccess)
                Text("Authenticated! Discovered \(count) server\(count == 1 ? "" : "s").")
                    .font(.mfCaption)
                    .foregroundColor(.mfSuccess)

                Button("Sign in Again") {
                    plexAuth.startOAuthFlow()
                }
                .font(.mfCaption)
                .foregroundColor(.mfPrimary)
                .buttonStyle(.plain)
            }

        case .expired:
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundColor(.mfWarning)
                Text("Authorization expired.")
                    .font(.mfCaption)
                    .foregroundColor(.mfWarning)

                Button("Try Again") {
                    plexAuth.startOAuthFlow()
                }
                .font(.mfCaption)
                .foregroundColor(.mfPrimary)
                .buttonStyle(.plain)
            }

        case .error(let message):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.mfError)
                Text(message)
                    .font(.mfCaption)
                    .foregroundColor(.mfError)
                    .lineLimit(2)

                Button("Retry") {
                    plexAuth.startOAuthFlow()
                }
                .font(.mfCaption)
                .foregroundColor(.mfPrimary)
                .buttonStyle(.plain)
            }
        }
    }

    private func connectPlex() async {
        isConnecting = true
        connectionStatus = ""

        do {
            let client = APIClient(baseURL: appState.backendURL)
            struct ConnectRequest: Codable { let url: String; let token: String }
            let server: PlexServerInfo = try await client.post("/api/plex/connect", body: ConnectRequest(url: plexURL, token: plexToken))

            if !appState.plexServers.contains(where: { $0.id == server.id }) {
                appState.plexServers.append(server)
            }
            appState.isConnected = true
            connectionStatus = "Success! Connected to \(server.name)"

            let _ = KeychainManager.save(key: "plex_token", value: plexToken)
        } catch {
            connectionStatus = "Failed: \(error.localizedDescription)"
        }

        isConnecting = false
    }

    private func refreshServers() async {
        do {
            let backend = BackendService()
            appState.plexServers = try await backend.getPlexServers()
            appState.isConnected = !appState.plexServers.isEmpty
        } catch {
            // Silently fail — server list will refresh on next health check
        }
    }
}

struct PlexServerRow: View {
    @EnvironmentObject var appState: AppState
    let server: PlexServerInfo
    let index: Int
    @State private var sshPanel: PlexSSHPanel?

    var body: some View {
        HStack {
            Image(systemName: "server.rack")
                .foregroundColor(.mfPrimary)
            VStack(alignment: .leading) {
                Text(server.name)
                    .font(.mfBodyMedium)
                Text(server.url)
                    .font(.mfCaption)
                    .foregroundColor(.mfTextMuted)
            }
            Spacer()

            if server.sshHostname != nil {
                Image(systemName: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundColor(.mfSuccess.opacity(0.8))
                    .help("SSH configured")
            }

            Text("\(server.libraryCount) libraries")
                .font(.mfCaption)
                .foregroundColor(.mfTextSecondary)

            Button {
                Task { await syncServer() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundColor(.mfPrimary)

            Button {
                openSSHPanel()
            } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                    .foregroundColor(.mfTextSecondary)
            }
            .buttonStyle(.plain)
            .help("Configure SSH")
        }
        .padding(12)
        .background(Color.mfSurfaceLight.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func syncServer() async {
        let client = APIClient(baseURL: appState.backendURL)
        struct SyncResponse: Codable { let status: String; let itemsSynced: Int; let librariesSynced: Int; let durationSeconds: Double }
        let _: SyncResponse? = try? await client.post("/api/plex/servers/\(server.id)/sync")
    }

    private func openSSHPanel() {
        let panel = PlexSSHPanel()
        sshPanel = panel
        panel.show(server: server, appState: appState, index: index) {
            sshPanel = nil
        }
    }
}

// MARK: - NSPanel for SSH config (keyboard input works here)

class PlexSSHPanel {
    private var panel: NSPanel?

    @MainActor
    func show(server: PlexServerInfo, appState: AppState, index: Int, onDismiss: @escaping () -> Void) {
        guard panel == nil else { return }

        let content = PlexSSHPanelContent(
            server: server,
            appState: appState,
            index: index,
            dismiss: { [weak self] in
                self?.close()
                onDismiss()
            }
        )

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: 460)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 460),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.title = "SSH Connection"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = false
        panel.center()
        panel.isReleasedWhenClosed = false
        self.panel = panel

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

struct PlexSSHPanelContent: View {
    let server: PlexServerInfo
    let appState: AppState
    let index: Int
    var dismiss: () -> Void

    @State private var sshHostname: String = ""
    @State private var sshPort: String = "22"
    @State private var sshUsername: String = ""
    @State private var sshKeyPath: String = ""
    @State private var sshPassword: String = ""
    @State private var benchmarkPath: String = ""
    @State private var isSaving: Bool = false
    @State private var isTesting: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case hostname, port, username, keyPath, password, benchmarkPath }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SSH Connection")
                        .font(.mfHeadline)
                    Text(server.name)
                        .font(.mfCaption)
                        .foregroundColor(.mfTextSecondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.mfTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .bottom)

            // Fields
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hostname / IP").font(.mfCaption).foregroundColor(.mfTextMuted)
                        TextField("192.168.1.100", text: $sshHostname)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .hostname)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Port").font(.mfCaption).foregroundColor(.mfTextMuted)
                        TextField("22", text: $sshPort)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .port)
                            .frame(width: 70)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Username").font(.mfCaption).foregroundColor(.mfTextMuted)
                    TextField("admin", text: $sshUsername)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .username)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Password").font(.mfCaption).foregroundColor(.mfTextMuted)
                        SecureField("Leave blank for key auth", text: $sshPassword)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .password)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("SSH Key Path").font(.mfCaption).foregroundColor(.mfTextMuted)
                        TextField("~/.ssh/id_rsa", text: $sshKeyPath)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .keyPath)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Benchmark Path").font(.mfCaption).foregroundColor(.mfTextMuted)
                    TextField("/share/ZFS18_DATA/Media/Plex", text: $benchmarkPath)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .benchmarkPath)
                    Text("Directory on Plex server for benchmark test files. Leave blank to auto-detect.")
                        .font(.system(size: 10))
                        .foregroundColor(.mfTextMuted)
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.mfCaption)
                        .foregroundColor(statusIsError ? .mfError : .mfSuccess)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(statusIsError ? Color.mfError.opacity(0.1) : Color.mfSuccess.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(20)

            Spacer()

            // Footer buttons
            HStack {
                Button {
                    Task { await testSSH() }
                } label: {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Text(isTesting ? "Testing..." : "Test SSH")
                    }
                    .secondaryButton()
                }
                .buttonStyle(.plain)
                .disabled(isTesting || sshHostname.isEmpty)

                Spacer()

                Button {
                    Task { await saveSSH() }
                } label: {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Text(isSaving ? "Saving..." : "Save SSH")
                    }
                    .primaryButton()
                }
                .buttonStyle(.plain)
                .disabled(isSaving || sshHostname.isEmpty)
            }
            .padding(20)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .top)
        }
        .frame(width: 440, height: 460)
        .background(Color.mfBackground)
        .preferredColorScheme(.dark)
        .onAppear {
            sshHostname = server.sshHostname ?? ""
            sshPort = "\(server.sshPort ?? 22)"
            sshUsername = server.sshUsername ?? ""
            sshKeyPath = server.sshKeyPath ?? ""
            sshPassword = server.sshPassword ?? ""
            benchmarkPath = server.benchmarkPath ?? ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedField = .hostname
            }
        }
    }

    private func saveSSH() async {
        isSaving = true
        statusMessage = ""
        do {
            let backend = BackendService()
            let request = PlexServerSSHRequest(
                sshHostname: sshHostname.isEmpty ? nil : sshHostname,
                sshPort: Int(sshPort) ?? 22,
                sshUsername: sshUsername.isEmpty ? nil : sshUsername,
                sshKeyPath: sshKeyPath.isEmpty ? nil : sshKeyPath,
                sshPassword: sshPassword.isEmpty ? nil : sshPassword,
                benchmarkPath: benchmarkPath.isEmpty ? nil : benchmarkPath
            )
            let updated = try await backend.updatePlexServerSSH(id: server.id, request: request)
            await MainActor.run {
                if index < appState.plexServers.count {
                    appState.plexServers[index] = updated
                }
            }
            statusMessage = "Saved successfully"
            statusIsError = false
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            statusIsError = true
        }
        isSaving = false
    }

    private func testSSH() async {
        isTesting = true
        statusMessage = ""
        do {
            let backend = BackendService()
            let result = try await backend.testPlexServerSSH(id: server.id)
            statusMessage = result.message
            statusIsError = result.status != "ok"
        } catch {
            statusMessage = "Test failed: \(error.localizedDescription)"
            statusIsError = true
        }
        isTesting = false
    }
}

// MARK: - Storage Settings

struct StorageSettingsView: View {
    @State private var mappings: [PathMapping] = []
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false

    private let service = BackendService()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Path Mappings
            VStack(alignment: .leading, spacing: 12) {
                Text("PATH MAPPINGS")
                    .mfSectionHeader()

                Text("Translate media paths from your Plex/NAS server to local mount points. Used when Plex reports paths like /share/... that are mounted locally at /Volumes/...")
                    .font(.mfBody)
                    .foregroundColor(.mfTextSecondary)

                if isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Loading mappings...")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextSecondary)
                    }
                } else {
                    ForEach(Array(mappings.enumerated()), id: \.element.id) { index, _ in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Source Path")
                                    .font(.mfCaption)
                                    .foregroundColor(.mfTextMuted)
                                TextField("/share/ZFS18_DATA/Media", text: $mappings[index].sourcePrefix)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Image(systemName: "arrow.right")
                                .foregroundColor(.mfTextMuted)
                                .padding(.top, 18)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Local Path")
                                    .font(.mfCaption)
                                    .foregroundColor(.mfTextMuted)
                                TextField("/Volumes/media", text: $mappings[index].targetPrefix)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Button {
                                mappings.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.mfError.opacity(0.8))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 18)
                        }
                        .padding(12)
                        .background(Color.mfSurfaceLight.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Button {
                        mappings.append(PathMapping(sourcePrefix: "", targetPrefix: ""))
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                            Text("Add Mapping")
                        }
                        .secondaryButton()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .cardStyle()

            // Save button
            if !isLoading {
                HStack {
                    Button {
                        Task { await saveMappings() }
                    } label: {
                        HStack(spacing: 4) {
                            if isSaving {
                                ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                            }
                            Text(isSaving ? "Saving..." : "Save Path Mappings")
                        }
                        .primaryButton()
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.mfCaption)
                            .foregroundColor(statusIsError ? .mfError : .mfSuccess)
                    }
                }
            }

            Spacer()
        }
        .task { await loadMappings() }
    }

    private func loadMappings() async {
        isLoading = true
        do {
            mappings = try await service.getPathMappings()
        } catch {
            statusMessage = "Failed to load mappings"
            statusIsError = true
        }
        isLoading = false
    }

    private func saveMappings() async {
        isSaving = true
        statusMessage = ""

        // Filter out rows where both fields are empty
        let filtered = mappings.filter { !$0.sourcePrefix.isEmpty || !$0.targetPrefix.isEmpty }

        // Warn about incomplete rows
        let incomplete = filtered.filter { $0.sourcePrefix.isEmpty || $0.targetPrefix.isEmpty }
        if !incomplete.isEmpty {
            statusMessage = "Some mappings have only one path filled in — please complete or remove them."
            statusIsError = true
            isSaving = false
            return
        }

        do {
            try await service.savePathMappings(filtered)
            mappings = filtered
            statusMessage = "Path mappings saved"
            statusIsError = false
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            statusIsError = true
        }
        isSaving = false
    }
}

// MARK: - Cloud GPU Settings

struct CloudGPUSettingsView: View {
    @State private var settings: CloudSettingsResponse?
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false
    @State private var apiKeyPanel: CloudAPIKeyPanel?

    // Editable fields
    @State private var monthlySpendCap: Double = 100
    @State private var instanceSpendCap: Double = 50
    @State private var defaultIdleMinutes: Double = 30
    @State private var selectedPlan: String = "vcg-a16-6c-64g-16vram"
    @State private var selectedRegion: String = "ewr"
    @State private var autoDeployEnabled: Bool = false
    @State private var plans: [CloudPlanInfo] = []

    private let service = BackendService()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Vultr API Key
            VStack(alignment: .leading, spacing: 12) {
                Text("VULTR API KEY")
                    .mfSectionHeader()

                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: settings?.apiKeyConfigured == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(settings?.apiKeyConfigured == true ? .mfSuccess : .mfError)
                        Text(settings?.apiKeyConfigured == true ? "API key configured" : "No API key set")
                            .font(.mfBody)
                            .foregroundColor(.mfTextSecondary)
                    }
                    Spacer()
                    Button {
                        openAPIKeyPanel()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "key")
                            Text(settings?.apiKeyConfigured == true ? "Change Key" : "Set API Key")
                        }
                        .primaryButton()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .cardStyle()

            // Spend Caps
            VStack(alignment: .leading, spacing: 12) {
                Text("SPEND CAPS")
                    .mfSectionHeader()

                Text("Auto-teardown cloud instances when spend limits are reached.")
                    .font(.mfBody)
                    .foregroundColor(.mfTextSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Monthly Cap")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                        Spacer()
                        Text("$\(Int(monthlySpendCap))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.mfPrimary)
                    }
                    .frame(maxWidth: 400)
                    Slider(value: $monthlySpendCap, in: 5...500, step: 5)
                        .frame(maxWidth: 400)
                        .tint(.mfPrimary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Per-Instance Cap")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                        Spacer()
                        Text("$\(Int(instanceSpendCap))")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.mfPrimary)
                    }
                    .frame(maxWidth: 400)
                    Slider(value: $instanceSpendCap, in: 5...200, step: 5)
                        .frame(maxWidth: 400)
                        .tint(.mfPrimary)
                }
            }
            .padding(20)
            .cardStyle()

            // Auto-Deploy
            VStack(alignment: .leading, spacing: 12) {
                Text("AUTO-DEPLOY")
                    .mfSectionHeader()

                Toggle(isOn: $autoDeployEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Auto-deploy cloud GPU when no workers are available")
                            .font(.mfBody)
                            .foregroundColor(.mfTextPrimary)
                        Text("Automatically deploys a cloud GPU instance using your default plan when transcode jobs are queued with no online workers.")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                    }
                }
                .toggleStyle(.switch)
                .tint(.mfPrimary)
            }
            .padding(20)
            .cardStyle()

            // Defaults
            VStack(alignment: .leading, spacing: 12) {
                Text("DEFAULTS")
                    .mfSectionHeader()

                if !plans.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Default GPU Plan")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                        Picker("", selection: $selectedPlan) {
                            ForEach(plans) { plan in
                                Text("\(plan.gpuModel) — \(plan.gpuVramGb) GB VRAM — $\(String(format: "%.3f", plan.hourlyCost))/hr")
                                    .tag(plan.planId)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: 500)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Default Idle Timeout")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                        Spacer()
                        Text("\(Int(defaultIdleMinutes)) min")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.mfPrimary)
                    }
                    .frame(maxWidth: 400)
                    Slider(value: $defaultIdleMinutes, in: 15...120, step: 5)
                        .frame(maxWidth: 400)
                        .tint(.mfPrimary)
                }
            }
            .padding(20)
            .cardStyle()

            // Save button
            HStack {
                Button {
                    Task { await saveSettings() }
                } label: {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Text(isSaving ? "Saving..." : "Save Cloud Settings")
                    }
                    .primaryButton()
                }
                .buttonStyle(.plain)
                .disabled(isSaving)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.mfCaption)
                        .foregroundColor(statusIsError ? .mfError : .mfSuccess)
                }
            }

            Spacer()
        }
        .task { await loadSettings() }
    }

    private func loadSettings() async {
        isLoading = true
        do {
            async let settingsReq = service.getCloudSettings()
            async let plansReq = service.getCloudPlans()
            let (s, p) = try await (settingsReq, plansReq)
            settings = s
            plans = p
            monthlySpendCap = s.monthlySpendCap
            instanceSpendCap = s.instanceSpendCap
            defaultIdleMinutes = Double(s.defaultIdleMinutes)
            selectedPlan = s.defaultPlan
            selectedRegion = s.defaultRegion
            autoDeployEnabled = s.autoDeployEnabled
        } catch {
            statusMessage = "Failed to load settings"
            statusIsError = true
        }
        isLoading = false
    }

    private func saveSettings() async {
        isSaving = true
        statusMessage = ""
        do {
            let request = CloudSettingsUpdate(
                defaultPlan: selectedPlan,
                defaultRegion: selectedRegion,
                monthlySpendCap: monthlySpendCap,
                instanceSpendCap: instanceSpendCap,
                defaultIdleMinutes: Int(defaultIdleMinutes),
                autoDeployEnabled: autoDeployEnabled
            )
            let updated = try await service.updateCloudSettings(request: request)
            settings = updated
            statusMessage = "Settings saved"
            statusIsError = false
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            statusIsError = true
        }
        isSaving = false
    }

    private func openAPIKeyPanel() {
        let panel = CloudAPIKeyPanel()
        apiKeyPanel = panel
        panel.show { [self] in
            apiKeyPanel = nil
            Task { await loadSettings() }
        }
    }
}

// MARK: - NSPanel for API key input

class CloudAPIKeyPanel {
    private var panel: NSPanel?

    @MainActor
    func show(onDismiss: @escaping () -> Void) {
        guard panel == nil else { return }

        let content = CloudAPIKeyPanelContent(dismiss: { [weak self] in
            self?.close()
            onDismiss()
        })

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 420, height: 220)

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.contentView = hostingView
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.isFloatingPanel = true
        p.level = .floating
        p.becomesKeyOnlyIfNeeded = false
        p.center()
        p.isReleasedWhenClosed = false
        self.panel = p

        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

struct CloudAPIKeyPanelContent: View {
    var dismiss: () -> Void
    @State private var apiKey: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Vultr API Key")
                    .font(.mfHeadline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.mfTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .bottom)

            VStack(alignment: .leading, spacing: 8) {
                Text("Enter your Vultr API key from the Vultr dashboard.")
                    .font(.mfCaption)
                    .foregroundColor(.mfTextSecondary)
                SecureField("Vultr API Key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.mfCaption)
                        .foregroundColor(.mfError)
                }
            }
            .padding(20)

            Spacer()

            HStack {
                Spacer()
                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Text(isSaving ? "Verifying..." : "Save API Key")
                    }
                    .primaryButton()
                }
                .buttonStyle(.plain)
                .disabled(isSaving || apiKey.isEmpty)
            }
            .padding(20)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .top)
        }
        .frame(width: 420, height: 220)
        .background(Color.mfBackground)
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focused = true
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = ""
        do {
            let service = BackendService()
            _ = try await service.updateCloudSettings(request: CloudSettingsUpdate(vultrApiKey: apiKey))
            dismiss()
        } catch {
            errorMessage = "Invalid API key or save failed: \(error.localizedDescription)"
        }
        isSaving = false
    }
}

struct NotificationSettingsView: View {
    @State private var configs: [NotificationConfigInfo] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String = ""
    @State private var emailPanel = EmailConfigPanel()
    @State private var webhookPanel = WebhookConfigPanel()
    @State private var pushPanel = PushConfigPanel()
    @State private var notificationHistory: [NotificationLogInfo] = []
    @State private var isLoadingHistory: Bool = true
    @State private var historyTotal: Int = 0

    private let service = BackendService()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("NOTIFICATION CHANNELS")
                    .mfSectionHeader()

                if isLoading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading...")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextSecondary)
                    }
                } else if configs.isEmpty {
                    Text("No notification channels configured yet.")
                        .font(.mfBody)
                        .foregroundColor(.mfTextMuted)
                } else {
                    ForEach(Array(configs.enumerated()), id: \.element.id) { index, config in
                        notificationRow(config: config, index: index)
                        if index < configs.count - 1 {
                            Divider().background(Color.mfGlassBorder)
                        }
                    }
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.mfCaption)
                        .foregroundColor(.mfError)
                }
            }
            .padding(20)
            .cardStyle()

            HStack(spacing: 10) {
                Button {
                    emailPanel.show { Task { await loadConfigs() } }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 11))
                        Text("Add Email")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .secondaryButton()
                }
                .buttonStyle(.plain)

                Button {
                    webhookPanel.show { Task { await loadConfigs() } }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                        Text("Add Webhook")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .secondaryButton()
                }
                .buttonStyle(.plain)

                Button {
                    webhookPanel.show(channelType: "discord") { Task { await loadConfigs() } }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 11))
                        Text("Add Discord")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .secondaryButton()
                }
                .buttonStyle(.plain)

                Button {
                    webhookPanel.show(channelType: "slack") { Task { await loadConfigs() } }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "number.square.fill")
                            .font(.system(size: 11))
                        Text("Add Slack")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .secondaryButton()
                }
                .buttonStyle(.plain)

                if !configs.contains(where: { $0.type == "push" }) {
                    Button {
                        pushPanel.show { Task { await loadConfigs() } }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "bell.badge.fill")
                                .font(.system(size: 11))
                            Text("Add Push")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .secondaryButton()
                    }
                    .buttonStyle(.plain)
                }
            }

            // Notification History
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("NOTIFICATION HISTORY")
                        .mfSectionHeader()
                    Spacer()
                    if historyTotal > 0 {
                        Text("\(historyTotal) total")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                    }
                    Button {
                        Task { await loadHistory() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.mfPrimary)
                    }
                    .buttonStyle(.plain)
                    .help("Refresh history")
                }

                if isLoadingHistory {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading history...")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextSecondary)
                    }
                } else if notificationHistory.isEmpty {
                    Text("No notifications sent yet. Notifications will appear here once channels are configured and events are triggered.")
                        .font(.mfBody)
                        .foregroundColor(.mfTextMuted)
                } else {
                    ForEach(notificationHistory) { log in
                        notificationHistoryRow(log: log)
                    }
                }
            }
            .padding(20)
            .cardStyle()

            Spacer()
        }
        .task {
            await loadConfigs()
            await loadHistory()
        }
    }

    private func notificationRow(config: NotificationConfigInfo, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notificationTypeIcon(config.type))
                .font(.system(size: 14))
                .foregroundColor(.mfPrimary)
                .frame(width: 28, height: 28)
                .background(Color.mfPrimary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.mfTextPrimary)
                Text(config.type.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.mfTextMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.mfSurfaceLight)
                    .clipShape(Capsule())
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { config.isEnabled },
                set: { newValue in
                    Task { await toggleEnabled(config: config, enabled: newValue) }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()

            Button {
                Task { await testConfig(config: config) }
            } label: {
                Image(systemName: "paperplane")
                    .font(.system(size: 11))
                    .foregroundColor(.mfTextMuted)
            }
            .buttonStyle(.plain)
            .help("Send test notification")

            Button {
                if config.type == "email" {
                    emailPanel.show(existingConfig: config) { Task { await loadConfigs() } }
                } else if config.type == "push" {
                    pushPanel.show(existingConfig: config) { Task { await loadConfigs() } }
                } else {
                    webhookPanel.show(existingConfig: config, channelType: config.type) { Task { await loadConfigs() } }
                }
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundColor(.mfTextMuted)
            }
            .buttonStyle(.plain)
            .help("Edit")

            Button {
                Task { await deleteConfig(config: config) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundColor(.mfTextMuted)
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func notificationHistoryRow(log: NotificationLogInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: notificationTypeIcon(log.channelType))
                .font(.system(size: 12))
                .foregroundColor(log.status == "sent" ? .mfSuccess : .mfError)
                .frame(width: 24, height: 24)
                .background((log.status == "sent" ? Color.mfSuccess : Color.mfError).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(formatEventName(log.event))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.mfTextPrimary)

                    Text(log.status.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(log.status == "sent" ? .mfSuccess : .mfError)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background((log.status == "sent" ? Color.mfSuccess : Color.mfError).opacity(0.15))
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    if let channelName = log.channelName {
                        Text(channelName)
                            .font(.system(size: 10))
                            .foregroundColor(.mfTextMuted)
                    }
                    Text(log.channelType.capitalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.mfTextMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.mfSurfaceLight)
                        .clipShape(Capsule())
                }

                if let errorMsg = log.errorMessage, !errorMsg.isEmpty {
                    Text(errorMsg)
                        .font(.system(size: 10))
                        .foregroundColor(.mfError)
                        .lineLimit(2)
                }
            }

            Spacer()

            if let createdAt = log.createdAt {
                Text(formatTimestamp(createdAt))
                    .font(.system(size: 10))
                    .foregroundColor(.mfTextMuted)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.mfSurfaceLight.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func loadConfigs() async {
        isLoading = true
        errorMessage = ""
        do {
            configs = try await service.getNotificationConfigs()
        } catch {
            errorMessage = "Failed to load: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func loadHistory() async {
        isLoadingHistory = true
        do {
            let response = try await service.getNotificationHistory(limit: 50)
            notificationHistory = response.items
            historyTotal = response.total
        } catch {
            // Silently fail — history is non-critical
        }
        isLoadingHistory = false
    }

    private func toggleEnabled(config: NotificationConfigInfo, enabled: Bool) async {
        do {
            _ = try await service.updateNotificationConfig(
                id: config.id,
                request: NotificationConfigUpdateRequest(isEnabled: enabled)
            )
            await loadConfigs()
        } catch {
            errorMessage = "Update failed: \(error.localizedDescription)"
        }
    }

    private func testConfig(config: NotificationConfigInfo) async {
        do {
            let result = try await service.testNotification(id: config.id)
            errorMessage = result.message
        } catch {
            errorMessage = "Test failed: \(error.localizedDescription)"
        }
    }

    private func deleteConfig(config: NotificationConfigInfo) async {
        do {
            try await service.deleteNotificationConfig(id: config.id)
            await loadConfigs()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }

    private func notificationTypeIcon(_ type: String) -> String {
        switch type {
        case "email": return "envelope.fill"
        case "discord": return "bubble.left.fill"
        case "slack": return "number.square.fill"
        case "telegram": return "paperplane.fill"
        case "webhook": return "link"
        case "push": return "bell.badge.fill"
        default: return "bell.fill"
        }
    }

    private func formatEventName(_ event: String) -> String {
        event.replacingOccurrences(of: ".", with: " ").split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func formatTimestamp(_ timestamp: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .short
        displayFormatter.timeStyle = .short

        // Try ISO 8601 first
        if let date = isoFormatter.date(from: timestamp) {
            return displayFormatter.string(from: date)
        }

        // Fallback: try common SQLite datetime format
        let sqlFormatter = DateFormatter()
        sqlFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        sqlFormatter.timeZone = TimeZone(abbreviation: "UTC")
        if let date = sqlFormatter.date(from: timestamp) {
            return displayFormatter.string(from: date)
        }

        return timestamp
    }
}

// MARK: - Scheduling Settings

struct SchedulingSettingsView: View {
    @State private var scheduleEnabled: Bool = false
    @State private var activeHoursStart: Date = SchedulingSettingsView.defaultTime(hour: 22, minute: 0)
    @State private var activeHoursEnd: Date = SchedulingSettingsView.defaultTime(hour: 6, minute: 0)
    @State private var activeDays: Set<Int> = Set(0...6)
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false
    @State private var maxRetries: Double = 3
    @State private var stuckTimeout: Double = 30
    @State private var syncScheduleEnabled: Bool = false
    @State private var syncInterval: String = "daily"
    @State private var webhookSources: [WebhookSourceInfo] = []
    @State private var watchFolders: [WatchFolderInfo] = []
    @State private var newWebhookName: String = ""
    @State private var newWebhookType: String = "sonarr"
    @State private var newWatchPath: String = ""

    private let service = BackendService()
    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    static func defaultTime(hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Library Sync Schedule
            VStack(alignment: .leading, spacing: 12) {
                Text("LIBRARY SYNC SCHEDULE")
                    .mfSectionHeader()

                Toggle(isOn: $syncScheduleEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable scheduled library sync")
                            .font(.mfBody)
                            .foregroundColor(.mfTextPrimary)
                        Text("Automatically sync Plex libraries on a recurring schedule. Optionally runs analysis after each sync.")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                    }
                }
                .toggleStyle(.switch)
                .tint(.mfPrimary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync Interval")
                        .font(.mfCaption)
                        .foregroundColor(.mfTextMuted)
                    Picker("Sync Interval", selection: $syncInterval) {
                        Text("Every 6 hours").tag("6h")
                        Text("Every 12 hours").tag("12h")
                        Text("Daily").tag("daily")
                        Text("Weekly").tag("weekly")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 400)
                }
                .opacity(syncScheduleEnabled ? 1.0 : 0.5)
                .allowsHitTesting(syncScheduleEnabled)
            }
            .padding(20)
            .cardStyle()

            // Enable/Disable
            VStack(alignment: .leading, spacing: 12) {
                Text("TRANSCODE SCHEDULING")
                    .mfSectionHeader()

                Toggle(isOn: $scheduleEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Enable scheduling")
                            .font(.mfBody)
                            .foregroundColor(.mfTextPrimary)
                        Text("Only process transcode jobs during the configured active hours and days. Jobs queued outside this window will wait until the next active period.")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                    }
                }
                .toggleStyle(.switch)
                .tint(.mfPrimary)
            }
            .padding(20)
            .cardStyle()

            // Active Hours
            VStack(alignment: .leading, spacing: 12) {
                Text("ACTIVE HOURS")
                    .mfSectionHeader()

                Text("Transcode jobs will only run between these times. Supports overnight windows (e.g. 22:00 to 06:00).")
                    .font(.mfBody)
                    .foregroundColor(.mfTextSecondary)

                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Start Time")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                        DatePicker("", selection: $activeHoursStart, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 100)
                    }

                    Image(systemName: "arrow.right")
                        .foregroundColor(.mfTextMuted)
                        .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("End Time")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                        DatePicker("", selection: $activeHoursEnd, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .frame(width: 100)
                    }

                    Spacer()
                }
            }
            .padding(20)
            .cardStyle()
            .opacity(scheduleEnabled ? 1.0 : 0.5)
            .allowsHitTesting(scheduleEnabled)

            // Active Days
            VStack(alignment: .leading, spacing: 12) {
                Text("ACTIVE DAYS")
                    .mfSectionHeader()

                Text("Select which days of the week transcoding is allowed.")
                    .font(.mfBody)
                    .foregroundColor(.mfTextSecondary)

                HStack(spacing: 8) {
                    ForEach(0..<7, id: \.self) { day in
                        Button {
                            if activeDays.contains(day) {
                                activeDays.remove(day)
                            } else {
                                activeDays.insert(day)
                            }
                        } label: {
                            Text(dayNames[day])
                                .font(.system(size: 12, weight: activeDays.contains(day) ? .semibold : .medium))
                                .foregroundColor(activeDays.contains(day) ? .white : .mfTextSecondary)
                                .frame(width: 44, height: 32)
                                .background(activeDays.contains(day) ? Color.mfPrimary : Color.mfSurfaceLight)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
            .cardStyle()
            .opacity(scheduleEnabled ? 1.0 : 0.5)
            .allowsHitTesting(scheduleEnabled)

            // Transcode Reliability
            VStack(alignment: .leading, spacing: 12) {
                Text("TRANSCODE RELIABILITY")
                    .mfSectionHeader()

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max Auto-Retries")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                        Spacer()
                        Text("\(Int(maxRetries)) retries")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.mfPrimary)
                    }
                    .frame(maxWidth: 450)
                    Slider(value: $maxRetries, in: 0...10, step: 1)
                        .frame(maxWidth: 450)
                        .tint(.mfPrimary)
                    Text("Number of automatic retry attempts for failed transcode jobs")
                        .font(.system(size: 10))
                        .foregroundColor(.mfTextMuted)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Stuck Job Timeout")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                        Spacer()
                        Text("\(Int(stuckTimeout)) min")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.mfPrimary)
                    }
                    .frame(maxWidth: 450)
                    Slider(value: $stuckTimeout, in: 10...120, step: 5)
                        .frame(maxWidth: 450)
                        .tint(.mfPrimary)
                    Text("Mark transcoding jobs as stuck if no progress update for this duration")
                        .font(.system(size: 10))
                        .foregroundColor(.mfTextMuted)
                }
            }
            .padding(20)
            .cardStyle()

            // Webhook Sources
            VStack(alignment: .leading, spacing: 12) {
                Text("WEBHOOK SOURCES")
                    .mfSectionHeader()

                Text("Receive webhooks from Sonarr/Radarr to auto-transcode new media.")
                    .font(.mfBody)
                    .foregroundColor(.mfTextSecondary)

                ForEach(webhookSources) { source in
                    HStack(spacing: 12) {
                        Image(systemName: source.sourceType == "sonarr" ? "tv" : "film")
                            .foregroundColor(.mfPrimary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(source.name)
                                .font(.system(size: 13, weight: .medium))
                            Text("POST /api/webhooks/ingest/\(source.id)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.mfTextMuted)
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Text("\(source.eventsReceived) events")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                        Button {
                            Task {
                                try? await service.deleteWebhookSource(id: source.id)
                                await loadWebhooks()
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.mfTextMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.mfSurfaceLight.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                HStack(spacing: 8) {
                    TextField("Source name", text: $newWebhookName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    Picker("Type", selection: $newWebhookType) {
                        Text("Sonarr").tag("sonarr")
                        Text("Radarr").tag("radarr")
                    }
                    .frame(width: 120)
                    Button {
                        guard !newWebhookName.isEmpty else { return }
                        Task {
                            _ = try? await service.createWebhookSource(
                                request: WebhookSourceCreateRequest(name: newWebhookName, sourceType: newWebhookType)
                            )
                            newWebhookName = ""
                            await loadWebhooks()
                        }
                    } label: {
                        Text("Add")
                            .secondaryButton()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .cardStyle()

            // Watch Folders
            VStack(alignment: .leading, spacing: 12) {
                Text("WATCH FOLDERS")
                    .mfSectionHeader()

                Text("Monitor directories for new media files and auto-queue transcode jobs.")
                    .font(.mfBody)
                    .foregroundColor(.mfTextSecondary)

                ForEach(watchFolders) { folder in
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.gearshape")
                            .foregroundColor(folder.isEnabled ? .mfPrimary : .mfTextMuted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(folder.path)
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                            Text("\(folder.filesProcessed) files processed")
                                .font(.mfCaption)
                                .foregroundColor(.mfTextMuted)
                        }
                        Spacer()
                        Button {
                            Task {
                                _ = try? await service.toggleWatchFolder(id: folder.id)
                                await loadWatchFolders()
                            }
                        } label: {
                            Image(systemName: folder.isEnabled ? "pause.circle" : "play.circle")
                                .foregroundColor(folder.isEnabled ? .mfSuccess : .mfTextMuted)
                        }
                        .buttonStyle(.plain)
                        Button {
                            Task {
                                try? await service.deleteWatchFolder(id: folder.id)
                                await loadWatchFolders()
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.mfTextMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.mfSurfaceLight.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.message = "Select a folder to watch for new media files"
                    if panel.runModal() == .OK, let url = panel.url {
                        Task {
                            _ = try? await service.createWatchFolder(
                                request: WatchFolderCreateRequest(path: url.path)
                            )
                            await loadWatchFolders()
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Watch Folder")
                    }
                    .secondaryButton()
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .cardStyle()

            // Save
            HStack {
                Button {
                    Task { await saveSettings() }
                } label: {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Text(isSaving ? "Saving..." : "Save Schedule Settings")
                    }
                    .primaryButton()
                }
                .buttonStyle(.plain)
                .disabled(isSaving)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.mfCaption)
                        .foregroundColor(statusIsError ? .mfError : .mfSuccess)
                }
            }

            Spacer()
        }
        .task { await loadSettings() }
    }

    private func timeToString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private func stringToDate(_ str: String) -> Date {
        let parts = str.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2 {
            return SchedulingSettingsView.defaultTime(hour: parts[0], minute: parts[1])
        }
        return Date()
    }

    private func loadSettings() async {
        isLoading = true
        do {
            let enabledResult = try await service.getScheduleSetting(key: "schedule.enabled")
            scheduleEnabled = enabledResult.value == "true"

            let startResult = try await service.getScheduleSetting(key: "schedule.active_hours_start")
            if let val = startResult.value {
                activeHoursStart = stringToDate(val)
            }

            let endResult = try await service.getScheduleSetting(key: "schedule.active_hours_end")
            if let val = endResult.value {
                activeHoursEnd = stringToDate(val)
            }

            let daysResult = try await service.getScheduleSetting(key: "schedule.active_days")
            if let val = daysResult.value {
                activeDays = Set(val.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
            }

            let retriesResult = try await service.getScheduleSetting(key: "transcode.max_retries")
            if let val = retriesResult.value, let num = Double(val) { maxRetries = num }

            let stuckResult = try await service.getScheduleSetting(key: "transcode.stuck_timeout_minutes")
            if let val = stuckResult.value, let num = Double(val) { stuckTimeout = num }

            let syncEnabledResult = try await service.getScheduleSetting(key: "sync.schedule_enabled")
            syncScheduleEnabled = syncEnabledResult.value == "true"

            let syncIntervalResult = try await service.getScheduleSetting(key: "sync.schedule_interval")
            if let val = syncIntervalResult.value, ["6h", "12h", "daily", "weekly"].contains(val) {
                syncInterval = val
            }
        } catch {
            // Use defaults on failure
        }
        isLoading = false
        await loadWebhooks()
        await loadWatchFolders()
    }

    private func saveSettings() async {
        isSaving = true
        statusMessage = ""
        do {
            let settings: [(String, String)] = [
                ("schedule.enabled", scheduleEnabled ? "true" : "false"),
                ("schedule.active_hours_start", timeToString(activeHoursStart)),
                ("schedule.active_hours_end", timeToString(activeHoursEnd)),
                ("schedule.active_days", activeDays.sorted().map(String.init).joined(separator: ",")),
                ("transcode.max_retries", "\(Int(maxRetries))"),
                ("transcode.stuck_timeout_minutes", "\(Int(stuckTimeout))"),
                ("sync.schedule_enabled", syncScheduleEnabled ? "true" : "false"),
                ("sync.schedule_interval", syncInterval),
            ]
            for (key, value) in settings {
                _ = try await service.setScheduleSetting(key: key, value: value)
            }
            statusMessage = "Schedule settings saved"
            statusIsError = false
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            statusIsError = true
        }
        isSaving = false
    }

    private func loadWebhooks() async {
        webhookSources = (try? await service.getWebhookSources()) ?? []
    }

    private func loadWatchFolders() async {
        watchFolders = (try? await service.getWatchFolders()) ?? []
    }
}

// MARK: - Intelligence Settings

struct IntelligenceSettingsView: View {
    @State private var autoAnalyze: Bool = true
    @State private var autoAnalyzeInterval: String = "disabled"
    @State private var overkillMinSizeGB: Double = 30
    @State private var overkillMaxPlays: Double = 2
    @State private var storageOptMinSizeGB: Double = 20
    @State private var storageOptTopN: Double = 20
    @State private var audioChannelsThreshold: Double = 6
    @State private var qualityGapPct: Double = 40
    @State private var hdrMaxPlays: Double = 3
    @State private var batchMinGroupSize: Double = 5
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false

    private let service = BackendService()

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Auto-Analyze
            VStack(alignment: .leading, spacing: 12) {
                Text("AUTO-ANALYZE")
                    .mfSectionHeader()

                Toggle(isOn: $autoAnalyze) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Run analysis automatically after library sync")
                            .font(.mfBody)
                            .foregroundColor(.mfTextPrimary)
                        Text("Automatically generates recommendations when new media is synced from Plex.")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                    }
                }
                .toggleStyle(.switch)
                .tint(.mfPrimary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Scheduled Auto-Analysis")
                        .font(.mfCaption)
                        .foregroundColor(.mfTextMuted)
                    Picker("Auto-Analysis Frequency", selection: $autoAnalyzeInterval) {
                        Text("Disabled").tag("disabled")
                        Text("Daily").tag("daily")
                        Text("Weekly").tag("weekly")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 300)
                    Text("Run full analysis on a recurring schedule, independent of library syncs.")
                        .font(.system(size: 10))
                        .foregroundColor(.mfTextMuted)
                }
            }
            .padding(20)
            .cardStyle()

            // Thresholds
            VStack(alignment: .leading, spacing: 16) {
                Text("ANALYSIS THRESHOLDS")
                    .mfSectionHeader()

                Text("Control what triggers recommendations. Higher thresholds = fewer recommendations.")
                    .font(.mfBody)
                    .foregroundColor(.mfTextSecondary)

                thresholdSlider(
                    label: "Quality Overkill Min Size",
                    value: $overkillMinSizeGB,
                    range: 5...100, step: 5,
                    suffix: "GB",
                    description: "Minimum file size to flag 4K HDR content as overkill"
                )

                thresholdSlider(
                    label: "Quality Overkill Max Plays",
                    value: $overkillMaxPlays,
                    range: 0...20, step: 1,
                    suffix: "plays",
                    description: "Maximum play count to consider 4K HDR content underused"
                )

                thresholdSlider(
                    label: "Storage Optimization Min Size",
                    value: $storageOptMinSizeGB,
                    range: 5...100, step: 5,
                    suffix: "GB",
                    description: "Minimum file size for storage optimization recommendations"
                )

                thresholdSlider(
                    label: "Storage Top N",
                    value: $storageOptTopN,
                    range: 5...100, step: 5,
                    suffix: "items",
                    description: "Number of largest files to analyze for storage optimization"
                )

                thresholdSlider(
                    label: "Audio Channels Threshold",
                    value: $audioChannelsThreshold,
                    range: 2...8, step: 1,
                    suffix: "ch",
                    description: "Minimum audio channels to flag for audio optimization"
                )

                thresholdSlider(
                    label: "Quality Gap Bitrate %",
                    value: $qualityGapPct,
                    range: 10...80, step: 5,
                    suffix: "%",
                    description: "Flag items below this percentage of average library bitrate"
                )

                thresholdSlider(
                    label: "HDR Max Plays",
                    value: $hdrMaxPlays,
                    range: 0...20, step: 1,
                    suffix: "plays",
                    description: "Maximum play count to flag HDR content for SDR conversion"
                )

                thresholdSlider(
                    label: "Batch Min Group Size",
                    value: $batchMinGroupSize,
                    range: 3...50, step: 1,
                    suffix: "files",
                    description: "Minimum group size for batch transcode recommendations"
                )
            }
            .padding(20)
            .cardStyle()

            // Save button
            HStack {
                Button {
                    Task { await saveSettings() }
                } label: {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Text(isSaving ? "Saving..." : "Save Intelligence Settings")
                    }
                    .primaryButton()
                }
                .buttonStyle(.plain)
                .disabled(isSaving)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.mfCaption)
                        .foregroundColor(statusIsError ? .mfError : .mfSuccess)
                }
            }

            Spacer()
        }
        .task { await loadSettings() }
    }

    @ViewBuilder
    private func thresholdSlider(label: String, value: Binding<Double>,
                                  range: ClosedRange<Double>, step: Double,
                                  suffix: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.mfCaption)
                    .foregroundColor(.mfTextMuted)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(suffix)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.mfPrimary)
            }
            .frame(maxWidth: 450)
            Slider(value: value, in: range, step: step)
                .frame(maxWidth: 450)
                .tint(.mfPrimary)
            Text(description)
                .font(.system(size: 10))
                .foregroundColor(.mfTextMuted)
        }
    }

    private func loadSettings() async {
        isLoading = true
        do {
            let keys: [(String, WritableKeyPath<IntelligenceSettingsView, Double>)] = [
                ("intel.overkill_min_size_gb", \.overkillMinSizeGB),
                ("intel.overkill_max_plays", \.overkillMaxPlays),
                ("intel.storage_opt_min_size_gb", \.storageOptMinSizeGB),
                ("intel.storage_opt_top_n", \.storageOptTopN),
                ("intel.audio_channels_threshold", \.audioChannelsThreshold),
                ("intel.quality_gap_bitrate_pct", \.qualityGapPct),
                ("intel.hdr_max_plays", \.hdrMaxPlays),
                ("intel.batch_min_group_size", \.batchMinGroupSize),
            ]

            for (key, _) in keys {
                let result = try await service.getIntelSetting(key: key)
                if let val = result.value, let num = Double(val) {
                    switch key {
                    case "intel.overkill_min_size_gb": overkillMinSizeGB = num
                    case "intel.overkill_max_plays": overkillMaxPlays = num
                    case "intel.storage_opt_min_size_gb": storageOptMinSizeGB = num
                    case "intel.storage_opt_top_n": storageOptTopN = num
                    case "intel.audio_channels_threshold": audioChannelsThreshold = num
                    case "intel.quality_gap_bitrate_pct": qualityGapPct = num
                    case "intel.hdr_max_plays": hdrMaxPlays = num
                    case "intel.batch_min_group_size": batchMinGroupSize = num
                    default: break
                    }
                }
            }

            let autoResult = try await service.getIntelSetting(key: "intel.auto_analyze_on_sync")
            autoAnalyze = autoResult.value != "false"

            let intervalResult = try await service.getIntelSetting(key: "intel.auto_analyze_interval")
            if let val = intervalResult.value, ["disabled", "daily", "weekly"].contains(val) {
                autoAnalyzeInterval = val
            }
        } catch {
            // Use defaults on failure
        }
        isLoading = false
    }

    private func saveSettings() async {
        isSaving = true
        statusMessage = ""
        do {
            let settings: [(String, String)] = [
                ("intel.auto_analyze_on_sync", autoAnalyze ? "true" : "false"),
                ("intel.auto_analyze_interval", autoAnalyzeInterval),
                ("intel.overkill_min_size_gb", "\(Int(overkillMinSizeGB))"),
                ("intel.overkill_max_plays", "\(Int(overkillMaxPlays))"),
                ("intel.storage_opt_min_size_gb", "\(Int(storageOptMinSizeGB))"),
                ("intel.storage_opt_top_n", "\(Int(storageOptTopN))"),
                ("intel.audio_channels_threshold", "\(Int(audioChannelsThreshold))"),
                ("intel.quality_gap_bitrate_pct", "\(Int(qualityGapPct))"),
                ("intel.hdr_max_plays", "\(Int(hdrMaxPlays))"),
                ("intel.batch_min_group_size", "\(Int(batchMinGroupSize))"),
            ]
            for (key, value) in settings {
                _ = try await service.setIntelSetting(key: key, value: value)
            }
            statusMessage = "Settings saved"
            statusIsError = false
        } catch {
            statusMessage = "Save failed: \(error.localizedDescription)"
            statusIsError = true
        }
        isSaving = false
    }
}

struct APISettingsView: View {
    @State private var apiToken: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("API ACCESS")
                    .mfSectionHeader()

                Text("Use this token for external API access.")
                    .font(.mfBody)
                    .foregroundColor(.mfTextSecondary)

                HStack {
                    TextField("API Token", text: $apiToken)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 400)

                    Button("Generate") {
                        apiToken = UUID().uuidString
                    }
                    .secondaryButton()
                }
            }
            .padding(20)
            .cardStyle()

            Spacer()
        }
    }
}
