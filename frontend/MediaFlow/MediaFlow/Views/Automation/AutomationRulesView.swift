import SwiftUI

@MainActor
class AutomationViewModel: ObservableObject {
    @Published var rules: [AutomationRule] = []
    @Published var isLoading = false

    private let service = BackendService()

    func loadRules() async {
        isLoading = true
        do { rules = try await service.getAutomationRules() } catch { print("Failed to load rules: \(error)") }
        isLoading = false
    }

    func toggleRule(_ id: Int) async {
        do {
            let updated = try await service.toggleAutomationRule(id: id)
            if let idx = rules.firstIndex(where: { $0.id == id }) { rules[idx] = updated }
        } catch { print("Failed to toggle rule: \(error)") }
    }

    func deleteRule(_ id: Int) async {
        do {
            try await service.deleteAutomationRule(id: id)
            rules.removeAll { $0.id == id }
        } catch { print("Failed to delete rule: \(error)") }
    }

    func createRule(name: String, triggerType: String) async {
        do {
            let request = AutomationRuleCreateRequest(name: name, triggerType: triggerType)
            let rule = try await service.createAutomationRule(request: request)
            rules.insert(rule, at: 0)
        } catch { print("Failed to create rule: \(error)") }
    }
}

struct AutomationRulesView: View {
    @StateObject private var viewModel = AutomationViewModel()
    @State private var showCreateForm = false
    @State private var newRuleName = ""
    @State private var newTriggerType = "analysis_complete"

    let triggerTypes = [
        ("analysis_complete", "Analysis Completes"),
        ("job_complete", "Job Completes"),
        ("job_failed", "Job Fails"),
        ("library_sync", "Library Syncs"),
        ("storage_threshold", "Storage Threshold"),
        ("schedule", "Schedule"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automation Rules")
                        .font(.system(size: 16, weight: .bold))
                    Text("Configure trigger → action workflows")
                        .font(.system(size: 12))
                        .foregroundColor(.mfTextSecondary)
                }
                Spacer()
                Button {
                    showCreateForm.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("New Rule")
                    }
                    .primaryButton()
                }
                .buttonStyle(.plain)
            }

            // Create form
            if showCreateForm {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Create New Rule")
                        .font(.system(size: 13, weight: .semibold))

                    HStack(spacing: 12) {
                        TextField("Rule name", text: $newRuleName)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)

                        Picker("Trigger", selection: $newTriggerType) {
                            ForEach(triggerTypes, id: \.0) { value, label in
                                Text(label).tag(value)
                            }
                        }
                        .frame(maxWidth: 200)

                        Button("Create") {
                            guard !newRuleName.isEmpty else { return }
                            Task {
                                await viewModel.createRule(name: newRuleName, triggerType: newTriggerType)
                                newRuleName = ""
                                showCreateForm = false
                            }
                        }
                        .primaryButton()
                        .buttonStyle(.plain)

                        Button("Cancel") { showCreateForm = false }
                            .buttonStyle(.plain)
                            .foregroundColor(.mfTextMuted)
                    }
                }
                .padding(16)
                .background(Color.mfSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Rules list
            if viewModel.rules.isEmpty && !viewModel.isLoading {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.mfTextMuted)
                    Text("No automation rules yet")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.mfTextSecondary)
                    Text("Create rules to automate your media optimization workflow.")
                        .font(.system(size: 12))
                        .foregroundColor(.mfTextMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                ForEach(viewModel.rules) { rule in
                    HStack(spacing: 14) {
                        // Enable toggle
                        Toggle("", isOn: Binding(
                            get: { rule.isEnabled },
                            set: { _ in Task { await viewModel.toggleRule(rule.id) } }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.7)

                        // Rule info
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(rule.isEnabled ? .mfTextPrimary : .mfTextMuted)

                            HStack(spacing: 8) {
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt")
                                        .font(.system(size: 9))
                                    Text(rule.triggerDisplayName)
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.mfPrimary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.mfPrimary.opacity(0.1))
                                .clipShape(Capsule())

                                if rule.triggerCount > 0 {
                                    Text("Triggered \(rule.triggerCount)x")
                                        .font(.system(size: 10))
                                        .foregroundColor(.mfTextMuted)
                                }
                            }
                        }

                        Spacer()

                        // Delete button
                        Button {
                            Task { await viewModel.deleteRule(rule.id) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12))
                                .foregroundColor(.mfError.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .background(Color.mfSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(rule.isEnabled ? Color.mfPrimary.opacity(0.15) : Color.mfGlassBorder, lineWidth: 1)
                    )
                }
            }
        }
        .task { await viewModel.loadRules() }
    }
}
