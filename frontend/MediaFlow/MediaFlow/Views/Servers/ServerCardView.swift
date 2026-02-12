import SwiftUI

struct ServerCardView: View {
    let server: WorkerServer
    var metrics: ServerStatus? = nil
    var benchmark: BenchmarkResult? = nil
    var isBenchmarking: Bool = false
    var benchmarkCompleted: Bool = false
    var benchmarkError: String? = nil
    var isProvisioning: Bool = false
    var provisionStep: ProvisionProgress? = nil
    var provisionCompleted: Bool = false
    var provisionError: String? = nil
    var cloudDeployProgress: CloudDeployProgress? = nil
    var cloudDeployError: String? = nil
    var onEdit: (() -> Void)? = nil
    var onBenchmark: (() -> Void)? = nil
    var onProvision: (() -> Void)? = nil
    var onTeardown: (() -> Void)? = nil
    @State private var showingLogs = false
    @State private var showTeardownConfirm = false

    var statusColor: Color {
        if !server.isEnabled { return .mfTextMuted }
        if server.isCloud {
            switch server.cloudStatus {
            case "creating", "bootstrapping": return .mfPrimary
            case "active": return .mfSuccess
            case "destroying": return .mfWarning
            case "destroyed", "failed": return .mfError
            default: break
            }
        }
        switch server.status {
        case "online": return .mfSuccess
        case "offline": return .mfError
        case "provisioning": return .mfPrimary
        case "setup_failed": return .mfError
        default: return .mfWarning
        }
    }

    var cloudRunningTime: String? {
        guard server.isCloud, let created = server.cloudCreatedAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: created) ?? ISO8601DateFormatter().date(from: created) else { return nil }
        let elapsed = Date().timeIntervalSince(date)
        let hours = Int(elapsed) / 3600
        let minutes = (Int(elapsed) % 3600) / 60
        let cost = elapsed / 3600 * (server.hourlyCost ?? 0)
        if hours > 0 {
            return String(format: "$%.2f (%dh %dm running)", cost, hours, minutes)
        }
        return String(format: "$%.2f (%dm running)", cost, minutes)
    }

    var cpuValue: Double {
        guard let pct = metrics?.cpuPercent else { return 0 }
        return pct / 100.0
    }

    var gpuValue: Double {
        guard let pct = metrics?.gpuPercent else { return 0 }
        return pct / 100.0
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    HStack(spacing: 10) {
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.mfSurfaceLight)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Image(systemName: server.isCloud ? "cloud.fill" : (server.isLocal ? "desktopcomputer" : "server.rack"))
                                        .foregroundColor(server.isCloud ? .mfPrimary : .mfTextMuted)
                                )
                            Circle()
                                .fill(statusColor)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.mfSurface, lineWidth: 2))
                                .offset(x: 4, y: -4)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.name.uppercased())
                                .font(.system(size: 13, weight: .bold))
                            HStack(spacing: 6) {
                                Text("Status: \(server.isEnabled ? server.status.capitalized : "Disabled")")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(statusColor)
                                    .textCase(.uppercase)
                                    .tracking(0.5)
                                if let score = server.performanceScore {
                                    Text("\(Int(score))")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(scoreColor(score))
                                        .clipShape(Capsule())
                                }
                            }

                            // Cloud badge
                            if server.isCloud {
                                HStack(spacing: 4) {
                                    Image(systemName: "cloud.bolt.fill")
                                        .font(.system(size: 8))
                                    Text(server.cloudPlan ?? "Cloud")
                                        .lineLimit(1)
                                }
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.mfPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.mfPrimary.opacity(0.1))
                                .clipShape(Capsule())
                            }
                        }
                    }
                    Spacer()
                    Button { onEdit?() } label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.mfTextMuted)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // Cloud deploy progress
                if let progress = cloudDeployProgress {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(progress.message)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.mfTextSecondary)
                                .lineLimit(2)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.mfSurfaceLight)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.mfPrimary)
                                    .frame(width: geo.size.width * CGFloat(progress.progress) / 100.0)
                                    .animation(.easeInOut(duration: 0.4), value: progress.progress)
                            }
                        }
                        .frame(height: 6)
                        Text("\(progress.progress)%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.mfPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 4)
                    .background(Color.mfPrimary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfPrimary.opacity(0.1)))
                } else if !server.isEnabled {
                    // Disabled state
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 24))
                            .foregroundColor(.mfTextMuted.opacity(0.5))
                        Text("AUTO-DISABLED")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.mfTextMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.mfSurfaceLight.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if server.status == "offline" {
                    // Offline state
                    VStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 24))
                            .foregroundColor(.mfError.opacity(0.7))
                        Text("RECONNECTING...")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.mfError)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.mfError.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfError.opacity(0.1)))
                } else if provisionCompleted {
                    // Just finished provisioning
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.mfSuccess)
                        Text("SETUP COMPLETE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.mfSuccess)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.mfSuccess.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfSuccess.opacity(0.15)))
                } else if let error = cloudDeployError {
                    // Cloud deploy failed
                    VStack(spacing: 8) {
                        Image(systemName: "cloud.bolt.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.mfError)
                        Text("CLOUD DEPLOY FAILED")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.mfError)
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.mfTextSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.mfError.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfError.opacity(0.1)))
                } else if let error = provisionError {
                    // Provision failed
                    VStack(spacing: 8) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.mfError)
                        Text("SETUP FAILED")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.mfError)
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.mfTextSecondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(.horizontal, 8)
                        Button { onProvision?() } label: {
                            Text("RETRY")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.mfPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.mfPrimary.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.mfError.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfError.opacity(0.1)))
                } else if isProvisioning {
                    // Provisioning in progress
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(provisionStep?.message ?? "Setting up server...")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.mfTextSecondary)
                                .lineLimit(1)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.mfSurfaceLight)
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.mfPrimary)
                                    .frame(width: geo.size.width * CGFloat(provisionStep?.progress ?? 0) / 100.0)
                                    .animation(.easeInOut(duration: 0.4), value: provisionStep?.progress)
                            }
                        }
                        .frame(height: 6)
                        Text("\(provisionStep?.progress ?? 0)%")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.mfPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 4)
                    .background(Color.mfPrimary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfPrimary.opacity(0.1)))
                } else if server.status == "pending" || server.status == "setup_failed" {
                    // Needs setup
                    VStack(spacing: 10) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 24))
                            .foregroundColor(.mfWarning)
                        Text("SERVER NEEDS SETUP")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.mfWarning)
                        Text("ffmpeg and dependencies are not installed.")
                            .font(.system(size: 10))
                            .foregroundColor(.mfTextMuted)
                        Button { onProvision?() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 11))
                                Text("INSTALL FFMPEG")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.mfPrimary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.mfWarning.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfWarning.opacity(0.1)))
                } else {
                    // CPU/GPU bars with live data
                    VStack(spacing: 12) {
                        ResourceBar(
                            label: server.cpuModel ?? "CPU",
                            value: cpuValue,
                            color: .mfPrimary
                        )
                        ResourceBar(
                            label: server.gpuModel ?? "GPU",
                            value: gpuValue,
                            color: .mfWarning
                        )
                    }

                    // Job counts
                    if let m = metrics, (m.activeJobs > 0 || m.queuedJobs > 0) {
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Circle().fill(Color.mfPrimary).frame(width: 6, height: 6)
                                Text("\(m.activeJobs) active")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.mfTextSecondary)
                            }
                            if m.queuedJobs > 0 {
                                HStack(spacing: 4) {
                                    Circle().fill(Color.mfWarning).frame(width: 6, height: 6)
                                    Text("\(m.queuedJobs) queued")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.mfTextSecondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }

                // Bottom stats
                HStack(spacing: 8) {
                    if let temp = metrics?.gpuTemp {
                        MiniStat(label: "Temperature", value: "\(Int(temp))\u{00B0}C")
                    } else {
                        MiniStat(label: "Temperature", value: "--")
                    }
                    if let fan = metrics?.fanSpeed {
                        MiniStat(label: "Fan Speed", value: "\(fan) RPM")
                    } else if let bench = benchmark, bench.status == "completed" {
                        MiniStat(
                            label: "Upload",
                            value: bench.uploadMbps.map { String(format: "%.0f Mbps", $0) } ?? "--"
                        )
                    } else {
                        MiniStat(label: "Fan Speed", value: "--")
                    }
                    if let bench = benchmark, bench.status == "completed" {
                        MiniStat(
                            label: "Download",
                            value: bench.downloadMbps.map { String(format: "%.0f Mbps", $0) } ?? "--"
                        )
                    } else if let mappings = server.pathMappings, !mappings.isEmpty {
                        MiniStat(label: "Path Maps", value: "\(mappings.count)")
                    }
                }
            }
            .padding(16)

            // Footer
            HStack {
                if server.isCloud, let runTime = cloudRunningTime {
                    Text(runTime)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.mfWarning)
                } else {
                    Text(server.ramGb.map { "\(Int($0)) GB RAM" } ?? "--")
                        .font(.mfCaption)
                        .foregroundColor(.mfTextMuted)
                }
                Spacer()

                if server.status == "online" || server.isLocal {
                    if let error = benchmarkError {
                        Text(error)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.mfError)
                            .lineLimit(2)
                            .frame(maxWidth: 180, alignment: .trailing)
                            .padding(.trailing, 12)
                    } else {
                        Button {
                            onBenchmark?()
                        } label: {
                            HStack(spacing: 4) {
                                if isBenchmarking {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text("RUNNING...")
                                        .foregroundColor(.mfPrimary)
                                } else if benchmarkCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.mfSuccess)
                                    Text("COMPLETED")
                                        .foregroundColor(.mfSuccess)
                                } else {
                                    Image(systemName: "speedometer")
                                        .font(.system(size: 10))
                                        .foregroundColor(.mfPrimary)
                                    Text("BENCHMARK")
                                        .foregroundColor(.mfPrimary)
                                }
                            }
                            .font(.system(size: 10, weight: .bold))
                            .animation(.easeInOut(duration: 0.3), value: isBenchmarking)
                            .animation(.easeInOut(duration: 0.3), value: benchmarkCompleted)
                        }
                        .buttonStyle(.plain)
                        .disabled(isBenchmarking || benchmarkCompleted)
                        .padding(.trailing, 12)
                    }
                }

                if server.isCloud && server.cloudStatus == "active" {
                    Button {
                        showTeardownConfirm = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("TEARDOWN")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.mfError)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                    .alert("Tear Down Cloud GPU?", isPresented: $showTeardownConfirm) {
                        Button("Cancel", role: .cancel) { }
                        Button("Tear Down", role: .destructive) { onTeardown?() }
                    } message: {
                        Text("This will destroy the Vultr instance and stop billing. Any active jobs will be cancelled.")
                    }
                }

                Button("VIEW LOGS") { showingLogs.toggle() }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.mfPrimary)
                    .buttonStyle(.plain)
                    .popover(isPresented: $showingLogs, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Job History")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.mfTextMuted)
                                .textCase(.uppercase)
                                .tracking(1)
                            Text("No transcode jobs have run on this server yet.")
                                .font(.mfCaption)
                                .foregroundColor(.mfTextSecondary)
                        }
                        .padding(12)
                        .frame(width: 240)
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.mfSurface.opacity(0.3))
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .top)
        }
        .background(Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.mfPrimary.opacity(0.1)))
        .opacity(server.status == "offline" && server.isEnabled ? 0.6 : (server.isEnabled ? 1.0 : 0.4))
    }

    private func scoreColor(_ score: Double) -> Color {
        if score >= 75 { return .mfSuccess }
        if score >= 40 { return .mfWarning }
        return .mfError
    }
}

struct ResourceBar: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.mfCaption)
                    .foregroundColor(.mfTextMuted)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.system(size: 11, weight: .bold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.mfSurfaceLight)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * min(1, max(0, value)))
                }
            }
            .frame(height: 6)
        }
    }
}

struct MiniStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.mfTextMuted)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 14, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.mfSurface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfGlassBorder.opacity(0.5)))
    }
}
