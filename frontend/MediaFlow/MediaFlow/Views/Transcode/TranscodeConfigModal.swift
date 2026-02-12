import SwiftUI
import AppKit

// MARK: - NSPanel-based presenter

class TranscodeConfigPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var onDismissCallback: (() -> Void)?

    @MainActor
    func show(mediaItemIds: [Int], totalSize: Int, onDismiss: @escaping () -> Void = {}) {
        guard panel == nil else { return }
        self.onDismissCallback = onDismiss

        let content = TranscodeConfigModal(
            dismiss: { [weak self] in
                self?.close()
            },
            mediaItems: [],
            bulkItemIds: mediaItemIds,
            bulkTotalSize: totalSize
        )

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
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
        panel.delegate = self
        panel.center()
        panel.isReleasedWhenClosed = false
        self.panel = panel

        panel.makeKeyAndOrderFront(nil)
    }

    @MainActor
    func show(mediaItems: [MediaItem], onDismiss: @escaping () -> Void = {}) {
        guard panel == nil else { return }
        self.onDismissCallback = onDismiss

        let content = TranscodeConfigModal(
            dismiss: { [weak self] in
                self?.close()
            },
            mediaItems: mediaItems
        )

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1000, height: 700)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
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
        panel.delegate = self
        panel.center()
        panel.isReleasedWhenClosed = false
        self.panel = panel

        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.close()
        panel = nil
        let cb = onDismissCallback
        onDismissCallback = nil
        cb?()
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        let cb = onDismissCallback
        onDismissCallback = nil
        cb?()
    }
}

// MARK: - Transcode config content

struct TranscodeConfigModal: View {
    var dismiss: () -> Void
    @StateObject private var viewModel = TranscodeConfigViewModel()
    let mediaItems: [MediaItem]
    var bulkItemIds: [Int] = []
    var bulkTotalSize: Int = 0
    var onQueue: (() -> Void)? = nil

    let resolutionOptions = ["4K", "1080p", "720p", "SD"]
    let codecOptions = [
        ("HEVC (H.265)", "libx265"),
        ("AV1", "libsvtav1"),
        ("H.264 (AVC)", "libx264"),
    ]
    let containerOptions = [
        ("MKV Container", "mkv"),
        ("MP4 Container", "mp4"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundColor(.mfPrimary)
                    Text("Transcode Configuration")
                        .font(.system(size: 18, weight: .bold))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.mfTextSecondary)
                        .padding(6)
                        .background(Color.mfSurfaceLight)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .bottom)

            // Scrollable Content
            ScrollView {
                VStack(spacing: 24) {
                    // Quick Presets
                    VStack(alignment: .leading, spacing: 12) {
                        Text("QUICK PRESETS")
                            .mfSectionHeader()

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(viewModel.presets) { preset in
                                PresetCard(preset: preset, isSelected: viewModel.selectedPreset?.id == preset.id) {
                                    viewModel.applyPreset(preset)
                                }
                            }
                        }
                    }

                    // Source / Target Split
                    HStack(spacing: 0) {
                        // Source
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.mfError).frame(width: 6, height: 6)
                                    Text("Source File").font(.system(size: 14, weight: .bold))
                                }
                                Spacer()
                                Text("ORIGINAL")
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.mfSurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }

                            if let source = viewModel.sourceItem {
                                VStack(spacing: 12) {
                                    InfoRow(label: "Resolution", value: "\(source.width ?? 0) x \(source.height ?? 0) (\(source.resolutionTier ?? "Unknown"))")
                                    InfoRow(label: "Bitrate", value: source.formattedBitrate + " Mbps")
                                    InfoRow(label: "Codec", value: source.codecDisplayName)
                                    InfoRow(label: "Frame Rate", value: source.frameRate.map { String(format: "%.3f fps", $0) } ?? "--")

                                    Divider().background(Color.mfGlassBorder)

                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("Total Size").font(.mfCaption).foregroundColor(.mfTextMuted)
                                            Text(viewModel.totalSourceSize.formattedFileSize)
                                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        }
                                        Spacer()
                                        Image(systemName: "externaldrive")
                                            .font(.system(size: 28))
                                            .foregroundColor(.mfTextMuted.opacity(0.3))
                                    }
                                }
                            } else if !viewModel.bulkItemIds.isEmpty {
                                VStack(spacing: 12) {
                                    InfoRow(label: "Items Selected", value: "\(viewModel.bulkItemIds.count)")

                                    Divider().background(Color.mfGlassBorder)

                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("Total Size").font(.mfCaption).foregroundColor(.mfTextMuted)
                                            Text(viewModel.totalSourceSize.formattedFileSize)
                                                .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        }
                                        Spacer()
                                        Image(systemName: "externaldrive")
                                            .font(.system(size: 28))
                                            .foregroundColor(.mfTextMuted.opacity(0.3))
                                    }
                                }
                            }
                        }
                        .padding(20)
                        .background(Color.mfSurface.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.mfGlassBorder))

                        // Arrow
                        VStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.mfPrimary)
                                    .frame(width: 36, height: 36)
                                    .shadow(color: .mfPrimary.opacity(0.3), radius: 8)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                            }
                            Spacer()
                        }
                        .frame(width: 60)

                        // Target
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                HStack(spacing: 6) {
                                    Circle().fill(Color.mfPrimary).frame(width: 6, height: 6)
                                    Text("Target Configuration").font(.system(size: 14, weight: .bold))
                                }
                                Spacer()
                                if let reduction = viewModel.estimatedReduction {
                                    HStack(spacing: 2) {
                                        Image(systemName: "arrow.down")
                                            .font(.system(size: 9, weight: .bold))
                                        Text("\(Int(reduction))% REDUCTION")
                                            .font(.system(size: 10, weight: .bold))
                                    }
                                    .foregroundColor(.mfSuccess)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.mfSuccess.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }

                            // Codec & Container
                            VStack(alignment: .leading, spacing: 6) {
                                Text("CODEC & CONTAINER").font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(1)
                                HStack(spacing: 8) {
                                    Picker("Codec", selection: $viewModel.videoCodec) {
                                        ForEach(codecOptions, id: \.1) { option in
                                            Text(option.0).tag(option.1)
                                        }
                                    }
                                    .labelsHidden()

                                    Picker("Container", selection: $viewModel.container) {
                                        ForEach(containerOptions, id: \.1) { option in
                                            Text(option.0).tag(option.1)
                                        }
                                    }
                                    .labelsHidden()
                                }
                            }

                            // Resolution
                            VStack(alignment: .leading, spacing: 6) {
                                Text("TARGET RESOLUTION").font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(1)
                                HStack(spacing: 6) {
                                    ForEach(resolutionOptions, id: \.self) { res in
                                        Button {
                                            viewModel.targetResolution = res
                                        } label: {
                                            Text(res)
                                                .font(.system(size: 12, weight: .medium))
                                                .padding(.horizontal, 16)
                                                .padding(.vertical, 8)
                                                .background(viewModel.targetResolution == res ? Color.mfPrimary : Color.clear)
                                                .foregroundColor(viewModel.targetResolution == res ? .white : .mfTextSecondary)
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(viewModel.targetResolution == res ? Color.clear : Color.mfGlassBorder, lineWidth: 1)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            // Bitrate Slider
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("TARGET BITRATE").font(.system(size: 10, weight: .bold)).foregroundColor(.mfTextMuted).tracking(1)
                                    Spacer()
                                    Text(String(format: "%.1f Mbps", viewModel.targetBitrate))
                                        .font(.mfMono)
                                        .foregroundColor(.mfPrimary)
                                }
                                Slider(value: $viewModel.targetBitrate, in: 1...50)
                                    .tint(.mfPrimary)
                                HStack {
                                    Text("Lower Quality").font(.system(size: 9)).foregroundColor(.mfTextMuted)
                                    Spacer()
                                    Text("Visually Lossless").font(.system(size: 9)).foregroundColor(.mfTextMuted)
                                }
                            }

                            Divider().background(Color.mfGlassBorder)

                            // Estimated output
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Estimated Size").font(.mfCaption).foregroundColor(.mfTextMuted)
                                    Text(viewModel.estimatedSize?.formattedFileSize ?? "--")
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .foregroundColor(.mfPrimary)
                                }
                                Spacer()
                                if let est = viewModel.estimatedSize {
                                    let savings = viewModel.totalSourceSize - est
                                    HStack(spacing: 4) {
                                        Image(systemName: "bolt")
                                            .font(.system(size: 11))
                                        Text("Saves \(savings.formattedFileSize)")
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                    .foregroundColor(.mfSuccess)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.mfSuccess.opacity(0.1))
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(20)
                        .background(Color.mfPrimary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.mfPrimary.opacity(0.2)))
                    }

                    // HW Accel Toggle
                    HStack {
                        HStack(spacing: 12) {
                            Image(systemName: "memorychip")
                                .foregroundColor(.mfWarning)
                                .padding(8)
                                .background(Color.mfWarning.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading) {
                                Text("Hardware Acceleration")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Enable GPU encoding for faster processing")
                                    .font(.mfCaption)
                                    .foregroundColor(.mfTextMuted)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.hwAccel)
                            .labelsHidden()
                            .tint(.mfPrimary)
                    }
                    .padding(16)
                    .background(Color.mfSurface.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.mfGlassBorder, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    )

                    // Server Assignment
                    if !viewModel.availableServers.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("SERVER ASSIGNMENT")
                                .mfSectionHeader()

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    // Auto option
                                    ServerPickerCard(
                                        name: "Auto",
                                        subtitle: "Recommended",
                                        icon: "sparkles",
                                        isSelected: viewModel.selectedServerId == nil,
                                        gpuModel: nil,
                                        loadFraction: nil,
                                        performanceScore: nil
                                    ) {
                                        viewModel.selectedServerId = nil
                                    }

                                    ForEach(viewModel.availableServers) { server in
                                        ServerPickerCard(
                                            name: server.name,
                                            subtitle: server.isLocal ? "Local" : (server.gpuModel ?? "Remote"),
                                            icon: server.isLocal ? "desktopcomputer" : "server.rack",
                                            isSelected: viewModel.selectedServerId == server.id,
                                            gpuModel: server.gpuModel,
                                            loadFraction: Double(server.activeJobs) / Double(max(server.maxConcurrentJobs, 1)),
                                            performanceScore: server.performanceScore
                                        ) {
                                            viewModel.selectedServerId = server.id
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }

            // Footer
            HStack {
                Button {
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.circle")
                        Text("Preview Sample (30s)")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.mfTextSecondary)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 10) {
                    Button {
                        Task {
                            if await viewModel.queueJobs() {
                                onQueue?()
                                dismiss()
                            }
                        }
                    } label: {
                        Text("Queue Task")
                            .secondaryButton()
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task {
                            if await viewModel.startNow() {
                                onQueue?()
                                dismiss()
                            }
                        }
                    } label: {
                        Text("Start Now")
                            .primaryButton()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color.mfSurface.opacity(0.8))
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .top)
        }
        .frame(width: 1000, height: 700)
        .background(Color.mfBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task {
            viewModel.mediaItems = mediaItems
            viewModel.bulkItemIds = bulkItemIds
            viewModel.bulkTotalSize = bulkTotalSize
            await viewModel.loadPresets()
            await viewModel.loadAvailableServers()
            if let first = viewModel.presets.first {
                viewModel.applyPreset(first)
            }
        }
    }
}

struct PresetCard: View {
    let preset: TranscodePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: preset.iconName)
                        .foregroundColor(isSelected ? .mfPrimary : .mfTextMuted)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.mfPrimary)
                            .font(.system(size: 14))
                    }
                }
                Text(preset.name)
                    .font(.system(size: 13, weight: .bold))
                Text(preset.description ?? "")
                    .font(.system(size: 11))
                    .foregroundColor(.mfTextMuted)
                    .lineLimit(2)
            }
            .padding(14)
            .background(isSelected ? Color.mfPrimary.opacity(0.05) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.mfPrimary : Color.mfGlassBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.mfCaption)
                .foregroundColor(.mfTextMuted)
            Spacer()
            Text(value)
                .font(.mfMono)
        }
    }
}

struct ServerPickerCard: View {
    let name: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    var gpuModel: String? = nil
    var loadFraction: Double? = nil
    var performanceScore: Double? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(isSelected ? .mfPrimary : .mfTextMuted)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.mfPrimary)
                            .font(.system(size: 14))
                    }
                }

                Text(name)
                    .font(.system(size: 13, weight: .bold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(.mfTextMuted)
                    .lineLimit(1)

                if let load = loadFraction {
                    HStack(spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.mfSurfaceLight)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(load > 0.8 ? Color.mfError : Color.mfPrimary)
                                    .frame(width: geo.size.width * min(1, max(0, load)))
                            }
                        }
                        .frame(height: 4)

                        if let score = performanceScore {
                            Text("\(Int(score))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(score >= 75 ? Color.mfSuccess : (score >= 40 ? Color.mfWarning : Color.mfError))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .padding(12)
            .frame(width: 140)
            .background(isSelected ? Color.mfPrimary.opacity(0.05) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.mfPrimary : Color.mfGlassBorder, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
