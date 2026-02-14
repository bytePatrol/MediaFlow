import SwiftUI
import AppKit

// MARK: - NSPanel-based presenter

class WebhookConfigPanel {
    private var panel: NSPanel?

    @MainActor
    func show(
        existingConfig: NotificationConfigInfo? = nil,
        channelType: String = "webhook",
        onSave: @escaping () -> Void
    ) {
        guard panel == nil else { return }

        let content = WebhookConfigPanelContent(
            dismiss: { [weak self] in self?.close() },
            existingConfig: existingConfig,
            channelType: channelType,
            onSave: onSave
        )

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: 520)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 520),
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

struct WebhookConfigPanelContent: View {
    var dismiss: () -> Void
    var existingConfig: NotificationConfigInfo?
    var channelType: String = "webhook"
    var onSave: () -> Void

    @State private var name: String = ""
    @State private var webhookUrl: String = ""
    @State private var availableEvents: [NotificationEventInfo] = []
    @State private var enabledEvents: Set<String> = ["job.completed", "job.failed"]
    @State private var isSaving: Bool = false
    @State private var isTesting: Bool = false
    @State private var errorMessage: String = ""
    @State private var testResult: String = ""

    private let service = BackendService()

    var isEditing: Bool { existingConfig != nil }

    private var channelTypeLabel: String {
        switch channelType {
        case "discord": return "Discord"
        case "slack": return "Slack"
        case "telegram": return "Telegram"
        default: return "Webhook"
        }
    }

    private var channelTypeIcon: String {
        switch channelType {
        case "discord": return "bubble.left.fill"
        case "slack": return "number.square.fill"
        case "telegram": return "paperplane.fill"
        default: return "link"
        }
    }

    private var channelTypeDescription: String {
        switch channelType {
        case "discord": return "Send notifications to a Discord channel via webhook."
        case "slack": return "Send notifications to a Slack channel via webhook."
        case "telegram": return "Send notifications to a Telegram chat via bot."
        default: return "POST JSON payloads to a URL on events."
        }
    }

    private var channelTypePlaceholder: String {
        switch channelType {
        case "discord": return "https://discord.com/api/webhooks/..."
        case "slack": return "https://hooks.slack.com/services/..."
        case "telegram": return "https://api.telegram.org/bot.../sendMessage"
        default: return "https://hooks.example.com/..."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: channelTypeIcon)
                            .foregroundColor(.mfPrimary)
                        Text(isEditing ? "Edit \(channelTypeLabel)" : "Add \(channelTypeLabel)")
                            .font(.mfHeadline)
                    }
                    Text(channelTypeDescription)
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NAME").font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(0.5)
                        TextField("My Webhook", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(channelTypeLabel.uppercased()) URL").font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(0.5)
                        TextField(channelTypePlaceholder, text: $webhookUrl)
                            .textFieldStyle(.roundedBorder)
                    }

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
        .frame(width: 440, height: 520)
        .background(Color.mfBackground)
        .preferredColorScheme(.dark)
        .onAppear { loadExisting() }
        .task { await loadEvents() }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !webhookUrl.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var selectedEvents: [String] {
        Array(enabledEvents)
    }

    private func loadExisting() {
        guard let config = existingConfig else { return }
        name = config.name
        let json = config.configJson ?? [:]
        webhookUrl = json["url"]?.value as? String ?? ""
        if let events = config.events, !events.isEmpty {
            enabledEvents = Set(events)
        }
    }

    private func loadEvents() async {
        do {
            availableEvents = try await service.getNotificationEvents()
        } catch {
            // Fallback to basic events if endpoint fails
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

    private func save() async {
        isSaving = true
        errorMessage = ""
        do {
            let configDict: [String: AnyCodable] = ["url": AnyCodable(webhookUrl)]
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
                        type: channelType,
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
            isTesting = true
            testResult = ""
            do {
                let configDict: [String: AnyCodable] = ["url": AnyCodable(webhookUrl)]
                let created = try await service.createNotificationConfig(
                    request: NotificationConfigCreateRequest(
                        type: channelType,
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
            let configDict: [String: AnyCodable] = ["url": AnyCodable(webhookUrl)]
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
