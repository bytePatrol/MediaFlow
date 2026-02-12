import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ManualTranscodeView: View {
    @EnvironmentObject var viewModel: TranscodeViewModel

    @State private var isCollapsed = false
    @State private var selectedFilePath: String?
    @State private var probeResult: ProbeResult?
    @State private var isProbing = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    // Settings state
    @State private var presets: [TranscodePreset] = []
    @State private var selectedPreset: TranscodePreset?
    @State private var videoCodec: String = "libx265"
    @State private var container: String = "mkv"
    @State private var targetResolution: String = "source"
    @State private var bitrateMode: String = "crf"
    @State private var crfValue: Double = 23
    @State private var targetBitrateMbps: Double = 8
    @State private var audioMode: String = "copy"
    @State private var servers: [ServerPickerItem] = []
    @State private var selectedServerId: Int?

    private let service = BackendService()
    private let videoFileTypes = ["mkv", "mp4", "avi", "mov", "wmv", "ts", "m4v", "webm"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.mfPrimary)
                    Text("Quick Transcode")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mfTextPrimary)
                    Spacer()
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background(Color.mfSurface)

            if !isCollapsed {
                HStack(alignment: .top, spacing: 16) {
                    // Left: File selection / drop zone
                    fileSelectionPanel
                        .frame(minWidth: 280, maxWidth: 340)

                    // Right: Settings
                    settingsPanel
                        .frame(minWidth: 300)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.mfSurface.opacity(0.5))
            }

            Rectangle()
                .fill(Color.mfGlassBorder)
                .frame(height: 1)
        }
        .task {
            await loadPresets()
            await loadServers()
        }
    }

    // MARK: - File Selection Panel

    private var fileSelectionPanel: some View {
        VStack(spacing: 12) {
            if let probe = probeResult {
                // File info display
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "film")
                            .font(.system(size: 14))
                            .foregroundColor(.mfPrimary)
                        Text(URL(fileURLWithPath: probe.filePath).lastPathComponent)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.mfTextPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            clearSelection()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.mfTextMuted)
                        }
                        .buttonStyle(.plain)
                    }

                    // Media info grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ], spacing: 8) {
                        infoChip(label: "Resolution", value: probe.resolution ?? "--")
                        infoChip(label: "Codec", value: (probe.videoCodec ?? "--").uppercased())
                        infoChip(label: "Bitrate", value: probe.formattedBitrate)
                        infoChip(label: "Size", value: probe.formattedSize)
                        infoChip(label: "Duration", value: probe.formattedDuration)
                        infoChip(label: "Audio", value: audioDescription(probe))
                    }
                }
                .padding(14)
                .glassPanel(cornerRadius: 10)
            } else {
                // Drop zone
                VStack(spacing: 10) {
                    if isProbing {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Analyzing file...")
                            .font(.system(size: 11))
                            .foregroundColor(.mfTextMuted)
                    } else {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 24))
                            .foregroundColor(.mfTextMuted)
                        Text("Select File or Drag & Drop")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.mfTextSecondary)
                        Text("MKV, MP4, AVI, MOV, TS, M4V")
                            .font(.system(size: 10))
                            .foregroundColor(.mfTextMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundColor(.mfGlassBorder)
                )
                .background(Color.mfGlass)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .onTapGesture {
                    openFilePicker()
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                    return true
                }
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.mfError)
            }
        }
    }

    // MARK: - Settings Panel

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Preset row
            if !presets.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PRESET")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                        .tracking(1)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(presets) { preset in
                                Button {
                                    applyPreset(preset)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: preset.iconName)
                                            .font(.system(size: 10))
                                        Text(preset.name)
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(selectedPreset?.id == preset.id ? Color.mfPrimary.opacity(0.2) : Color.mfSurfaceLight)
                                    .foregroundColor(selectedPreset?.id == preset.id ? .mfPrimary : .mfTextSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(selectedPreset?.id == preset.id ? Color.mfPrimary.opacity(0.4) : Color.mfGlassBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            // Codec + Container row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CODEC")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                        .tracking(1)
                    HStack(spacing: 0) {
                        codecButton("HEVC", value: "libx265")
                        codecButton("AV1", value: "libsvtav1")
                        codecButton("H.264", value: "libx264")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mfGlassBorder, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("CONTAINER")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                        .tracking(1)
                    HStack(spacing: 0) {
                        containerButton("MKV", value: "mkv")
                        containerButton("MP4", value: "mp4")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mfGlassBorder, lineWidth: 1))
                }
            }

            // Resolution + Audio row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RESOLUTION")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                        .tracking(1)
                    Picker("", selection: $targetResolution) {
                        Text("Source").tag("source")
                        Text("4K").tag("4K")
                        Text("1080p").tag("1080p")
                        Text("720p").tag("720p")
                        Text("SD").tag("SD")
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("AUDIO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                        .tracking(1)
                    HStack(spacing: 0) {
                        audioButton("Copy", value: "copy")
                        audioButton("Re-encode", value: "transcode")
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.mfGlassBorder, lineWidth: 1))
                }
            }

            // Bitrate slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("QUALITY (CRF)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                        .tracking(1)
                    Spacer()
                    Text("\(Int(crfValue))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.mfTextPrimary)
                }
                Slider(value: $crfValue, in: 15...35, step: 1)
                    .tint(.mfPrimary)
                HStack {
                    Text("Higher quality")
                        .font(.system(size: 9))
                        .foregroundColor(.mfTextMuted)
                    Spacer()
                    Text("Smaller file")
                        .font(.system(size: 9))
                        .foregroundColor(.mfTextMuted)
                }
            }

            // Server picker + Start button row
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SERVER")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                        .tracking(1)
                    Picker("", selection: $selectedServerId) {
                        Text("Auto").tag(nil as Int?)
                        ForEach(servers) { server in
                            Text(server.name).tag(server.id as Int?)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                Spacer()

                Button {
                    Task { await startTranscode() }
                } label: {
                    HStack(spacing: 6) {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 11))
                        }
                        Text("Start Transcode")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(probeResult != nil && !isSubmitting ? Color.mfPrimary : Color.mfPrimary.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(probeResult == nil || isSubmitting)
            }
        }
    }

    // MARK: - Segmented Button Helpers

    private func codecButton(_ label: String, value: String) -> some View {
        Button {
            videoCodec = value
            selectedPreset = nil
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(videoCodec == value ? .mfPrimary : .mfTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(videoCodec == value ? Color.mfPrimary.opacity(0.15) : Color.mfSurfaceLight)
        }
        .buttonStyle(.plain)
    }

    private func containerButton(_ label: String, value: String) -> some View {
        Button {
            container = value
            selectedPreset = nil
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(container == value ? .mfPrimary : .mfTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(container == value ? Color.mfPrimary.opacity(0.15) : Color.mfSurfaceLight)
        }
        .buttonStyle(.plain)
    }

    private func audioButton(_ label: String, value: String) -> some View {
        Button {
            audioMode = value
            selectedPreset = nil
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(audioMode == value ? .mfPrimary : .mfTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(audioMode == value ? Color.mfPrimary.opacity(0.15) : Color.mfSurfaceLight)
        }
        .buttonStyle(.plain)
    }

    private func infoChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.mfTextMuted)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.mfTextPrimary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func audioDescription(_ probe: ProbeResult) -> String {
        let codec = (probe.audioCodec ?? "--").uppercased()
        if let ch = probe.audioChannels {
            let chLabel = ch >= 6 ? "5.1" : ch == 2 ? "Stereo" : ch == 1 ? "Mono" : "\(ch)ch"
            return "\(codec) \(chLabel)"
        }
        return codec
    }

    // MARK: - Actions

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = videoFileTypes.compactMap {
            UTType(filenameExtension: $0)
        }
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { await selectFile(url.path) }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                let ext = url.pathExtension.lowercased()
                guard videoFileTypes.contains(ext) else { return }
                Task { @MainActor in
                    await selectFile(url.path)
                }
            }
        }
    }

    private func selectFile(_ path: String) async {
        selectedFilePath = path
        probeResult = nil
        errorMessage = nil
        isProbing = true
        do {
            probeResult = try await service.probeFile(path: path)
        } catch {
            errorMessage = "Failed to analyze file: \(error.localizedDescription)"
        }
        isProbing = false
    }

    private func clearSelection() {
        selectedFilePath = nil
        probeResult = nil
        errorMessage = nil
    }

    private func applyPreset(_ preset: TranscodePreset) {
        selectedPreset = preset
        videoCodec = preset.videoCodec
        container = preset.container
        if let crf = preset.crfValue { crfValue = Double(crf) }
        audioMode = preset.audioMode
        targetResolution = preset.targetResolution ?? "source"
    }

    private func loadPresets() async {
        do {
            presets = try await service.getPresets()
        } catch {
            print("Failed to load presets: \(error)")
        }
    }

    private func loadServers() async {
        do {
            servers = try await service.getAvailableServers()
        } catch {
            print("Failed to load servers: \(error)")
        }
    }

    private func startTranscode() async {
        guard let probe = probeResult else { return }
        isSubmitting = true
        errorMessage = nil

        var config: [String: AnyCodable] = [
            "video_codec": AnyCodable(videoCodec),
            "container": AnyCodable(container),
            "bitrate_mode": AnyCodable(bitrateMode),
            "crf_value": AnyCodable(Int(crfValue)),
            "audio_mode": AnyCodable(audioMode),
        ]
        if targetResolution != "source" {
            config["target_resolution"] = AnyCodable(targetResolution)
        }

        let request = ManualTranscodeRequest(
            filePath: probe.filePath,
            fileSize: probe.fileSize,
            config: config,
            presetId: selectedPreset?.id,
            priority: 10,
            preferredWorkerId: selectedServerId
        )

        do {
            _ = try await service.createManualTranscodeJob(request: request)
            // Clear file selection after successful submission
            clearSelection()
            // Refresh job list
            await viewModel.loadJobs()
            await viewModel.loadQueueStats()
        } catch {
            errorMessage = "Failed to start transcode: \(error.localizedDescription)"
        }
        isSubmitting = false
    }
}
