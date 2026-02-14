import SwiftUI
import AppKit

// MARK: - NSPanel-based presenter

class EmailConfigPanel {
    private var panel: NSPanel?

    @MainActor
    func show(
        existingConfig: NotificationConfigInfo? = nil,
        onSave: @escaping () -> Void
    ) {
        guard panel == nil else { return }

        let content = EmailConfigPanelContent(
            dismiss: { [weak self] in self?.close() },
            existingConfig: existingConfig,
            onSave: onSave
        )

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 500, height: 520)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 520),
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
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

// MARK: - Panel content

struct EmailConfigPanelContent: View {
    var dismiss: () -> Void
    var existingConfig: NotificationConfigInfo?
    var onSave: () -> Void

    @State private var name: String = ""
    @State private var smtpHost: String = ""
    @State private var smtpPort: String = "587"
    @State private var smtpUsername: String = ""
    @State private var smtpPassword: String = ""
    @State private var fromAddress: String = ""
    @State private var toAddress: String = ""
    @State private var useTls: Bool = true
    @State private var availableEvents: [NotificationEventInfo] = []
    @State private var enabledEvents: Set<String> = ["job.completed", "job.failed"]
    @State private var isSaving: Bool = false
    @State private var isTesting: Bool = false
    @State private var errorMessage: String = ""
    @State private var testResult: String = ""

    private let service = BackendService()

    var isEditing: Bool { existingConfig != nil }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.mfPrimary)
                        Text(isEditing ? "Edit Email Channel" : "Add Email Channel")
                            .font(.mfHeadline)
                    }
                    Text("Configure SMTP settings for email notifications.")
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

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    fieldRow(label: "NAME", placeholder: "My Email Alerts", text: $name)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SMTP HOST").font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(0.5)
                            TextField("smtp.gmail.com", text: $smtpHost)
                                .textFieldStyle(.roundedBorder)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("PORT").font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(0.5)
                            TextField("587", text: $smtpPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                    }

                    fieldRow(label: "USERNAME", placeholder: "user@gmail.com", text: $smtpUsername)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PASSWORD").font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(0.5)
                        SecureField("App password", text: $smtpPassword)
                            .textFieldStyle(.roundedBorder)
                    }

                    fieldRow(label: "FROM ADDRESS", placeholder: "alerts@example.com", text: $fromAddress)
                    fieldRow(label: "TO ADDRESS", placeholder: "you@example.com", text: $toAddress)

                    Toggle(isOn: $useTls) {
                        Text("Use TLS (STARTTLS)")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .toggleStyle(.switch)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("EVENTS").font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(0.5)
                        if availableEvents.isEmpty {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(availableEvents) { event in
                                Toggle(isOn: Binding(
                                    get: { enabledEvents.contains(event.event) },
                                    set: { enabled in
                                        if enabled { enabledEvents.insert(event.event) }
                                        else { enabledEvents.remove(event.event) }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(formatEventName(event.event))
                                            .font(.system(size: 12, weight: .medium))
                                        Text(event.description)
                                            .font(.system(size: 10))
                                            .foregroundColor(.mfTextMuted)
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.mfCaption)
                            .foregroundColor(.mfError)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.mfError.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }

                    if !testResult.isEmpty {
                        Text(testResult)
                            .font(.mfCaption)
                            .foregroundColor(testResult.contains("success") ? .green : .mfWarning)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.mfSurfaceLight)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(20)
            }

            // Footer
            HStack {
                Button { dismiss() } label: {
                    Text("Cancel").secondaryButton()
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task { await sendTest() }
                } label: {
                    HStack(spacing: 4) {
                        if isTesting {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Text("Send Test")
                    }
                    .secondaryButton()
                }
                .buttonStyle(.plain)
                .disabled(isTesting || !isValid)

                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: 4) {
                        if isSaving {
                            ProgressView().scaleEffect(0.7).frame(width: 14, height: 14)
                        }
                        Text(isEditing ? "Update" : "Save")
                    }
                    .primaryButton()
                }
                .buttonStyle(.plain)
                .disabled(isSaving || !isValid)
            }
            .padding(20)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .top)
        }
        .frame(width: 500, height: 520)
        .background(Color.mfBackground)
        .preferredColorScheme(.dark)
        .onAppear { loadExisting() }
        .task { await loadEvents() }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !smtpHost.trimmingCharacters(in: .whitespaces).isEmpty &&
        !toAddress.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func fieldRow(label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(0.5)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func loadExisting() {
        guard let config = existingConfig else { return }
        name = config.name
        let json = config.configJson ?? [:]
        smtpHost = json["smtp_host"]?.value as? String ?? ""
        smtpPort = "\(json["smtp_port"]?.value as? Int ?? 587)"
        smtpUsername = json["smtp_username"]?.value as? String ?? ""
        smtpPassword = json["smtp_password"]?.value as? String ?? ""
        fromAddress = json["from_address"]?.value as? String ?? ""
        toAddress = json["to_address"]?.value as? String ?? ""
        useTls = json["use_tls"]?.value as? Bool ?? true
        if let events = config.events, !events.isEmpty {
            enabledEvents = Set(events)
        }
    }

    private func loadEvents() async {
        do {
            availableEvents = try await service.getNotificationEvents()
        } catch {
            availableEvents = [
                NotificationEventInfo(event: "job.completed", description: "When a transcode job finishes successfully"),
                NotificationEventInfo(event: "job.failed", description: "When a transcode job fails"),
            ]
        }
    }

    private func formatEventName(_ event: String) -> String {
        event.replacingOccurrences(of: ".", with: " ").split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private var configDict: [String: AnyCodable] {
        [
            "smtp_host": AnyCodable(smtpHost),
            "smtp_port": AnyCodable(Int(smtpPort) ?? 587),
            "smtp_username": AnyCodable(smtpUsername),
            "smtp_password": AnyCodable(smtpPassword),
            "from_address": AnyCodable(fromAddress),
            "to_address": AnyCodable(toAddress),
            "use_tls": AnyCodable(useTls),
        ]
    }

    private var selectedEvents: [String] {
        Array(enabledEvents)
    }

    private func save() async {
        isSaving = true
        errorMessage = ""
        do {
            if let existing = existingConfig {
                _ = try await service.updateNotificationConfig(
                    id: existing.id,
                    request: NotificationConfigUpdateRequest(
                        name: name,
                        config: configDict,
                        events: selectedEvents,
                        isEnabled: true
                    )
                )
            } else {
                _ = try await service.createNotificationConfig(
                    request: NotificationConfigCreateRequest(
                        type: "email",
                        name: name,
                        config: configDict,
                        events: selectedEvents,
                        isEnabled: true
                    )
                )
            }
            onSave()
            dismiss()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
        isSaving = false
    }

    private func sendTest() async {
        guard let existing = existingConfig else {
            // Save first, then test
            isTesting = true
            testResult = ""
            do {
                let created = try await service.createNotificationConfig(
                    request: NotificationConfigCreateRequest(
                        type: "email",
                        name: name,
                        config: configDict,
                        events: selectedEvents,
                        isEnabled: true
                    )
                )
                let result = try await service.testNotification(id: created.id)
                testResult = result.message
                onSave()
                dismiss()
            } catch {
                testResult = "Test failed: \(error.localizedDescription)"
            }
            isTesting = false
            return
        }

        isTesting = true
        testResult = ""
        do {
            // Update config first, then test
            _ = try await service.updateNotificationConfig(
                id: existing.id,
                request: NotificationConfigUpdateRequest(
                    name: name,
                    config: configDict,
                    events: selectedEvents,
                    isEnabled: true
                )
            )
            let result = try await service.testNotification(id: existing.id)
            testResult = result.message
        } catch {
            testResult = "Test failed: \(error.localizedDescription)"
        }
        isTesting = false
    }
}
