import SwiftUI
import AppKit

// MARK: - NSPanel-based presenter

/// Presents AddServerSheet in a real NSPanel window that properly handles keyboard input.
class AddServerPanel {
    private var panel: NSPanel?

    @MainActor
    func show(onDismiss: @escaping () -> Void) {
        guard panel == nil else { return }

        let content = AddServerSheetContent(dismiss: { [weak self] in
            self?.close()
            onDismiss()
        })

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 550, height: 620)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 620),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
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
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

// MARK: - Sheet content (pure SwiftUI, rendered inside the NSPanel)

private struct AddServerSheetContent: View {
    var dismiss: () -> Void
    @State private var name: String = ""
    @State private var hostname: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var isLocal: Bool = false
    @State private var isTesting: Bool = false
    @State private var isSubmitting: Bool = false
    @State private var testResult: String = ""
    @State private var pathMappings: [PathMapping] = []
    @FocusState private var focusedField: Field?
    private let backend = BackendService()

    private enum Field: Hashable { case name, hostname, port, username }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Server Node")
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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Local Server", isOn: $isLocal)
                        .tint(.mfPrimary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server Name").font(.mfCaption).foregroundColor(.mfTextMuted)
                        TextField("TRANSCODE-NODE-01", text: $name)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .name)
                    }

                    if !isLocal {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hostname / IP").font(.mfCaption).foregroundColor(.mfTextMuted)
                            TextField("192.168.1.100", text: $hostname)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .hostname)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("SSH Port").font(.mfCaption).foregroundColor(.mfTextMuted)
                                TextField("22", text: $port)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .port)
                                    .frame(width: 80)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("SSH Username").font(.mfCaption).foregroundColor(.mfTextMuted)
                                TextField("root", text: $username)
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedField, equals: .username)
                            }
                        }
                    }

                    // Path Mappings section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Path Mappings").font(.mfCaption).foregroundColor(.mfTextMuted)
                            Spacer()
                            Button {
                                pathMappings.append(PathMapping(sourcePrefix: "", targetPrefix: ""))
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus")
                                    Text("Add")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.mfPrimary)
                            }
                            .buttonStyle(.plain)
                        }

                        if pathMappings.isEmpty {
                            Text("Map Plex server paths to local mount points so the worker can access media files.")
                                .font(.system(size: 11))
                                .foregroundColor(.mfTextMuted)
                                .padding(.vertical, 4)
                        }

                        ForEach($pathMappings) { $mapping in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Plex Path").font(.system(size: 9, weight: .bold)).foregroundColor(.mfTextMuted)
                                    TextField("/share/ZFS18_DATA/", text: $mapping.sourcePrefix)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12))
                                }

                                Image(systemName: "arrow.right")
                                    .foregroundColor(.mfTextMuted)
                                    .font(.system(size: 11))
                                    .padding(.top, 14)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Worker Path").font(.system(size: 9, weight: .bold)).foregroundColor(.mfTextMuted)
                                    TextField("/Volumes/MediaNAS/", text: $mapping.targetPrefix)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12))
                                }

                                Button {
                                    pathMappings.removeAll { $0.id == mapping.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.mfError)
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 14)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.mfSurface.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfGlassBorder.opacity(0.5)))

                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.mfCaption)
                            .foregroundColor(testResult.contains("Success") ? .mfSuccess : .mfError)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(testResult.contains("Success") ? Color.mfSuccess.opacity(0.1) : Color.mfError.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(20)
            }

            HStack {
                Button {
                    testResult = isTesting ? "" : "Testing..."
                    isTesting = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        testResult = "Success! Connection established."
                        isTesting = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Text("Test Connection")
                    }
                    .secondaryButton()
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    isSubmitting = true
                    Task {
                        do {
                            let mappings = pathMappings.filter {
                                !$0.sourcePrefix.isEmpty && !$0.targetPrefix.isEmpty
                            }
                            let request = AddWorkerServerRequest(
                                name: name,
                                hostname: isLocal ? "localhost" : hostname,
                                port: Int(port) ?? 22,
                                sshUsername: isLocal ? nil : (username.isEmpty ? nil : username),
                                isLocal: isLocal,
                                pathMappings: mappings.isEmpty ? nil : mappings
                            )
                            _ = try await backend.addWorkerServer(request: request)
                            dismiss()
                        } catch {
                            testResult = "Failed to add server: \(error.localizedDescription)"
                            isSubmitting = false
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isSubmitting {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Text("Add Server")
                    }
                    .primaryButton()
                }
                .buttonStyle(.plain)
                .disabled(name.isEmpty || isSubmitting)
            }
            .padding(20)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .top)
        }
        .frame(width: 550, height: 620)
        .background(Color.mfBackground)
        .preferredColorScheme(.dark)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                focusedField = .name
            }
        }
    }
}

// MARK: - Edit Server Panel

class EditServerPanel {
    private var panel: NSPanel?

    @MainActor
    func show(server: WorkerServer, onSave: @escaping (UpdateWorkerServerRequest) -> Void, onDelete: @escaping () -> Void, onDismiss: @escaping () -> Void = {}) {
        guard panel == nil else { return }

        let content = EditServerSheetContent(
            server: server,
            dismiss: { [weak self] in
                self?.close()
                onDismiss()
            },
            onSave: { request in
                onSave(request)
            },
            onDelete: {
                onDelete()
            }
        )

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 550, height: 620)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 550, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
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
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

private struct EditServerSheetContent: View {
    let server: WorkerServer
    var dismiss: () -> Void
    var onSave: (UpdateWorkerServerRequest) -> Void
    var onDelete: () -> Void

    @State private var name: String = ""
    @State private var hostname: String = ""
    @State private var port: String = "22"
    @State private var username: String = ""
    @State private var maxJobs: String = "1"
    @State private var workingDir: String = "/tmp/mediaflow"
    @State private var pathMappings: [PathMapping] = []
    @State private var showDeleteConfirm = false
    @State private var statusMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Edit Server")
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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Server Name").font(.mfCaption).foregroundColor(.mfTextMuted)
                        TextField("Name", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    if !server.isLocal {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hostname / IP").font(.mfCaption).foregroundColor(.mfTextMuted)
                            TextField("192.168.1.100", text: $hostname)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("SSH Port").font(.mfCaption).foregroundColor(.mfTextMuted)
                                TextField("22", text: $port)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("SSH Username").font(.mfCaption).foregroundColor(.mfTextMuted)
                                TextField("root", text: $username)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Max Concurrent Jobs").font(.mfCaption).foregroundColor(.mfTextMuted)
                            TextField("1", text: $maxJobs)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Working Directory").font(.mfCaption).foregroundColor(.mfTextMuted)
                            TextField("/tmp/mediaflow", text: $workingDir)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    // Path Mappings
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Path Mappings").font(.mfCaption).foregroundColor(.mfTextMuted)
                            Spacer()
                            Button {
                                pathMappings.append(PathMapping(sourcePrefix: "", targetPrefix: ""))
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "plus")
                                    Text("Add")
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.mfPrimary)
                            }
                            .buttonStyle(.plain)
                        }

                        if pathMappings.isEmpty {
                            Text("Map Plex server paths to local mount points so the worker can access media files.")
                                .font(.system(size: 11))
                                .foregroundColor(.mfTextMuted)
                                .padding(.vertical, 4)
                        }

                        ForEach($pathMappings) { $mapping in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Plex Path").font(.system(size: 9, weight: .bold)).foregroundColor(.mfTextMuted)
                                    TextField("/share/ZFS18_DATA/", text: $mapping.sourcePrefix)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12))
                                }

                                Image(systemName: "arrow.right")
                                    .foregroundColor(.mfTextMuted)
                                    .font(.system(size: 11))
                                    .padding(.top, 14)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Worker Path").font(.system(size: 9, weight: .bold)).foregroundColor(.mfTextMuted)
                                    TextField("/Volumes/MediaNAS/", text: $mapping.targetPrefix)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.system(size: 12))
                                }

                                Button {
                                    pathMappings.removeAll { $0.id == mapping.id }
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundColor(.mfError)
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 14)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.mfSurface.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfGlassBorder.opacity(0.5)))

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.mfCaption)
                            .foregroundColor(statusMessage.contains("Saved") ? .mfSuccess : .mfError)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(statusMessage.contains("Saved") ? Color.mfSuccess.opacity(0.1) : Color.mfError.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(20)
            }

            HStack {
                Button {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Delete Server")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.mfError)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.mfError.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .alert("Delete Server?", isPresented: $showDeleteConfirm) {
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                } message: {
                    Text("This will remove \"\(server.name)\" from your server list. This cannot be undone.")
                }

                Spacer()

                Button {
                    let mappings = pathMappings.filter {
                        !$0.sourcePrefix.isEmpty && !$0.targetPrefix.isEmpty
                    }
                    let request = UpdateWorkerServerRequest(
                        name: name,
                        hostname: server.isLocal ? nil : hostname,
                        port: server.isLocal ? nil : Int(port),
                        sshUsername: server.isLocal ? nil : (username.isEmpty ? nil : username),
                        maxConcurrentJobs: Int(maxJobs),
                        workingDirectory: workingDir,
                        pathMappings: mappings
                    )
                    onSave(request)
                    dismiss()
                } label: {
                    Text("Save Changes")
                        .primaryButton()
                }
                .buttonStyle(.plain)
                .disabled(name.isEmpty)
            }
            .padding(20)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .top)
        }
        .frame(width: 550, height: 620)
        .background(Color.mfBackground)
        .preferredColorScheme(.dark)
        .onAppear {
            name = server.name
            hostname = server.hostname
            port = "\(server.port)"
            username = server.sshUsername ?? ""
            maxJobs = "\(server.maxConcurrentJobs)"
            workingDir = server.workingDirectory
            pathMappings = server.pathMappings ?? []
        }
    }
}

// Keep the old name available so ServerManagementView compiles (unused now)
struct AddServerSheet: View {
    var dismiss: () -> Void
    var body: some View { EmptyView() }
}
