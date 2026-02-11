import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general = "General"
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
                switch selectedTab {
                case .general:
                    GeneralSettingsView()
                case .cloudGpu:
                    CloudGPUSettingsView()
                case .notifications:
                    NotificationSettingsView()
                case .api:
                    APISettingsView()
                }
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
        .onChange(of: plexAuth.authState) { newState in
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

// MARK: - Cloud GPU Settings

struct CloudGPUSettingsView: View {
    @State private var settings: CloudSettingsResponse?
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false
    @State private var apiKeyPanel: CloudAPIKeyPanel?

    // Editable fields
    @State private var monthlySpendCap: String = "100"
    @State private var instanceSpendCap: String = "50"
    @State private var defaultIdleMinutes: Double = 30
    @State private var selectedPlan: String = "vcg-a16-8c-64g-16vram"
    @State private var selectedRegion: String = "ewr"
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

                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Monthly Cap ($)")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                        TextField("100", text: $monthlySpendCap)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Per-Instance Cap ($)")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                        TextField("50", text: $instanceSpendCap)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 120)
                    }
                }
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
            monthlySpendCap = String(format: "%.0f", s.monthlySpendCap)
            instanceSpendCap = String(format: "%.0f", s.instanceSpendCap)
            defaultIdleMinutes = Double(s.defaultIdleMinutes)
            selectedPlan = s.defaultPlan
            selectedRegion = s.defaultRegion
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
                monthlySpendCap: Double(monthlySpendCap),
                instanceSpendCap: Double(instanceSpendCap),
                defaultIdleMinutes: Int(defaultIdleMinutes)
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
    @State private var jobCompleted: Bool = true
    @State private var jobFailed: Bool = true
    @State private var serverOffline: Bool = true
    @State private var batchCompleted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                Text("NOTIFICATION EVENTS")
                    .mfSectionHeader()

                Toggle("Job Completed", isOn: $jobCompleted)
                Toggle("Job Failed", isOn: $jobFailed)
                Toggle("Server Offline", isOn: $serverOffline)
                Toggle("Batch Completed", isOn: $batchCompleted)
            }
            .padding(20)
            .cardStyle()

            Spacer()
        }
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
