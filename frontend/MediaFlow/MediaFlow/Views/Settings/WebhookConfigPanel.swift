import SwiftUI
import AppKit

// MARK: - NSPanel-based presenter

class WebhookConfigPanel {
    private var panel: NSPanel?

    @MainActor
    func show(
        existingConfig: NotificationConfigInfo? = nil,
        onSave: @escaping () -> Void
    ) {
        guard panel == nil else { return }

        let content = WebhookConfigPanelContent(
            dismiss: { [weak self] in self?.close() },
            existingConfig: existingConfig,
            onSave: onSave
        )

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 440, height: 360)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
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
    var onSave: () -> Void

    @State private var name: String = ""
    @State private var webhookUrl: String = ""
    @State private var jobCompleted: Bool = true
    @State private var jobFailed: Bool = true
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
                        Image(systemName: "link")
                            .foregroundColor(.mfPrimary)
                        Text(isEditing ? "Edit Webhook" : "Add Webhook")
                            .font(.mfHeadline)
                    }
                    Text("POST JSON payloads to a URL on events.")
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

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("NAME").font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(0.5)
                    TextField("My Webhook", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("WEBHOOK URL").font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(0.5)
                    TextField("https://hooks.example.com/...", text: $webhookUrl)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("EVENTS").font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(0.5)
                    Toggle("Job Completed", isOn: $jobCompleted)
                        .toggleStyle(.checkbox)
                    Toggle("Job Failed", isOn: $jobFailed)
                        .toggleStyle(.checkbox)
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

                Spacer()
            }
            .padding(20)

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
        .frame(width: 440, height: 360)
        .background(Color.mfBackground)
        .preferredColorScheme(.dark)
        .onAppear { loadExisting() }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !webhookUrl.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var selectedEvents: [String] {
        var events: [String] = []
        if jobCompleted { events.append("job.completed") }
        if jobFailed { events.append("job.failed") }
        return events
    }

    private func loadExisting() {
        guard let config = existingConfig else { return }
        name = config.name
        let json = config.configJson ?? [:]
        webhookUrl = json["url"]?.value as? String ?? ""
        let events = config.events ?? []
        jobCompleted = events.contains("job.completed")
        jobFailed = events.contains("job.failed")
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
                        type: "webhook",
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
                        type: "webhook",
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
