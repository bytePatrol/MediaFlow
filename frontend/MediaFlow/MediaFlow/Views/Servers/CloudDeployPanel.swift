import SwiftUI
import AppKit

// MARK: - NSPanel-based presenter

class CloudDeployPanel {
    private var panel: NSPanel?

    @MainActor
    func show(onDeploy: @escaping () -> Void) {
        guard panel == nil else { return }

        let content = CloudDeployPanelContent(dismiss: { [weak self] in
            self?.close()
        }, onDeploy: {
            onDeploy()
        })

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 520)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
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

struct CloudDeployPanelContent: View {
    var dismiss: () -> Void
    var onDeploy: () -> Void

    @State private var plans: [CloudPlanInfo] = []
    @State private var selectedPlan: String = "vcg-a16-8c-64g-16vram"
    @State private var selectedRegion: String = "ewr"
    @State private var idleMinutes: Double = 30
    @State private var autoTeardown: Bool = true
    @State private var isLoading: Bool = true
    @State private var isDeploying: Bool = false
    @State private var errorMessage: String = ""
    @State private var cloudSettings: CloudSettingsResponse?

    private let service = BackendService()

    private let regionNames: [String: String] = [
        "ewr": "New Jersey", "ord": "Chicago", "dfw": "Dallas",
        "sea": "Seattle", "lax": "Los Angeles", "atl": "Atlanta",
        "ams": "Amsterdam", "lhr": "London", "fra": "Frankfurt",
        "nrt": "Tokyo", "sgp": "Singapore", "syd": "Sydney",
    ]

    var selectedPlanInfo: CloudPlanInfo? {
        plans.first(where: { $0.planId == selectedPlan })
    }

    var availableRegions: [String] {
        selectedPlanInfo?.regions ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "cloud.bolt.fill")
                            .foregroundColor(.mfPrimary)
                        Text("Deploy Cloud GPU")
                            .font(.mfHeadline)
                    }
                    Text("Spin up an on-demand GPU instance for transcoding.")
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

            if isLoading {
                Spacer()
                ProgressView("Loading plans...")
                    .foregroundColor(.mfTextSecondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // GPU Plan picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("GPU PLAN")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.mfTextMuted)
                                .tracking(0.5)

                            Picker("", selection: $selectedPlan) {
                                ForEach(plans) { plan in
                                    HStack {
                                        Text(plan.gpuModel)
                                        Text("\(plan.gpuVramGb) GB VRAM")
                                            .foregroundColor(.mfTextSecondary)
                                        Text("$\(String(format: "%.3f", plan.hourlyCost))/hr")
                                            .foregroundColor(.mfTextMuted)
                                    }
                                    .tag(plan.planId)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        // Plan details card
                        if let plan = selectedPlanInfo {
                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("GPU").font(.system(size: 9, weight: .bold)).foregroundColor(.mfTextMuted)
                                    Text(plan.gpuModel).font(.system(size: 13, weight: .semibold))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("VRAM").font(.system(size: 9, weight: .bold)).foregroundColor(.mfTextMuted)
                                    Text("\(plan.gpuVramGb) GB").font(.system(size: 13, weight: .semibold))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("vCPUs").font(.system(size: 9, weight: .bold)).foregroundColor(.mfTextMuted)
                                    Text("\(plan.vcpus)").font(.system(size: 13, weight: .semibold))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("RAM").font(.system(size: 9, weight: .bold)).foregroundColor(.mfTextMuted)
                                    Text("\(plan.ramMb / 1024) GB").font(.system(size: 13, weight: .semibold))
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("COST").font(.system(size: 9, weight: .bold)).foregroundColor(.mfTextMuted)
                                    Text("$\(String(format: "%.3f", plan.hourlyCost))/hr")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.mfPrimary)
                                }
                            }
                            .padding(12)
                            .background(Color.mfSurfaceLight.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfGlassBorder.opacity(0.5)))
                        }

                        // Region picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("REGION")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.mfTextMuted)
                                .tracking(0.5)

                            if availableRegions.isEmpty {
                                Text("Configure your Vultr API key in Settings to see available regions.")
                                    .font(.mfCaption)
                                    .foregroundColor(.mfTextMuted)
                            } else {
                                Picker("", selection: $selectedRegion) {
                                    ForEach(availableRegions, id: \.self) { region in
                                        Text("\(regionNames[region] ?? region) (\(region.uppercased()))")
                                            .tag(region)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }

                        // Idle timeout
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("IDLE TIMEOUT")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.mfTextMuted)
                                    .tracking(0.5)
                                Spacer()
                                Text("\(Int(idleMinutes)) min")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.mfPrimary)
                            }
                            Slider(value: $idleMinutes, in: 15...120, step: 5)
                                .tint(.mfPrimary)
                            Text("Instance auto-destroys after this many minutes with no active jobs.")
                                .font(.system(size: 10))
                                .foregroundColor(.mfTextMuted)
                        }

                        // Auto-teardown toggle
                        Toggle(isOn: $autoTeardown) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Auto-Teardown")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Automatically destroy when idle. Disable to keep running.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.mfTextMuted)
                            }
                        }
                        .toggleStyle(.switch)

                        // Spend cap info
                        if let settings = cloudSettings {
                            HStack(spacing: 8) {
                                Image(systemName: "shield.checkered")
                                    .foregroundColor(.mfWarning)
                                    .font(.system(size: 12))
                                Text("Spend caps: $\(String(format: "%.0f", settings.monthlySpendCap))/mo, $\(String(format: "%.0f", settings.instanceSpendCap))/instance")
                                    .font(.system(size: 11))
                                    .foregroundColor(.mfTextSecondary)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.mfWarning.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
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
                    }
                    .padding(20)
                }
            }

            // Footer
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .secondaryButton()
                }
                .buttonStyle(.plain)

                Spacer()

                if let plan = selectedPlanInfo {
                    Text("Est. $\(String(format: "%.2f", plan.hourlyCost * idleMinutes / 60))/session")
                        .font(.system(size: 11))
                        .foregroundColor(.mfTextMuted)
                }

                Button {
                    Task { await deploy() }
                } label: {
                    HStack(spacing: 6) {
                        if isDeploying {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "bolt.fill")
                        }
                        Text(isDeploying ? "Deploying..." : "Deploy")
                    }
                    .primaryButton()
                }
                .buttonStyle(.plain)
                .disabled(isDeploying || selectedPlan.isEmpty)
            }
            .padding(20)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .top)
        }
        .frame(width: 480, height: 520)
        .background(Color.mfBackground)
        .preferredColorScheme(.dark)
        .task {
            await loadData()
        }
    }

    private func loadData() async {
        isLoading = true
        do {
            async let plansReq = service.getCloudPlans()
            async let settingsReq = service.getCloudSettings()
            let (fetchedPlans, fetchedSettings) = try await (plansReq, settingsReq)
            plans = fetchedPlans
            cloudSettings = fetchedSettings
            selectedPlan = fetchedSettings.defaultPlan
            selectedRegion = fetchedSettings.defaultRegion
            idleMinutes = Double(fetchedSettings.defaultIdleMinutes)
        } catch {
            errorMessage = "Failed to load plans: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func deploy() async {
        isDeploying = true
        errorMessage = ""
        do {
            let request = CloudDeployRequest(
                plan: selectedPlan,
                region: selectedRegion,
                idleMinutes: Int(idleMinutes),
                autoTeardown: autoTeardown
            )
            _ = try await service.deployCloudGPU(request: request)
            onDeploy()
            dismiss()
        } catch {
            errorMessage = "Deploy failed: \(error.localizedDescription)"
        }
        isDeploying = false
    }
}
