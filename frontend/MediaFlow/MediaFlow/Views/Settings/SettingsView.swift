import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general = "General"
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
        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: 400)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
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
    @State private var isSaving: Bool = false
    @State private var isTesting: Bool = false
    @State private var statusMessage: String = ""
    @State private var statusIsError: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable { case hostname, port, username, keyPath, password }

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
        .frame(width: 440, height: 400)
        .background(Color.mfBackground)
        .preferredColorScheme(.dark)
        .onAppear {
            sshHostname = server.sshHostname ?? ""
            sshPort = "\(server.sshPort ?? 22)"
            sshUsername = server.sshUsername ?? ""
            sshKeyPath = server.sshKeyPath ?? ""
            sshPassword = server.sshPassword ?? ""
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
                sshPassword: sshPassword.isEmpty ? nil : sshPassword
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
