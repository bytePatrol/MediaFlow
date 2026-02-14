import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct QuickTranscodePageView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: TranscodeViewModel

    @State private var selectedFilePath: String?
    @State private var probeResult: ProbeResult?
    @State private var isProbing = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

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
        VStack(spacing: 0) {
            // Page header
            HStack(spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.mfPrimary)
                    Text("Quick Transcode")
                        .font(.mfHeadline)
                }

                Divider()
                    .frame(height: 30)

                Text("Transcode any local video file outside of your Plex library")
                    .font(.system(size: 12))
                    .foregroundColor(.mfTextMuted)

                Spacer()

                Button {
                    appState.selectedNavItem = .processing
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape.2")
                            .font(.system(size: 11))
                        Text("View Queue")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .secondaryButton()
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color.mfSurface)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .bottom)

            // Main content
            ScrollView {
                VStack(spacing: 24) {
                    HStack(alignment: .top, spacing: 24) {
                        // Left: File selection / drop zone
                        fileSelectionPanel
                            .frame(minWidth: 320, idealWidth: 400, maxWidth: 480)

                        // Right: Settings
                        settingsPanel
                            .frame(minWidth: 360)
                    }
                    .padding(24)
                    .glassPanel(cornerRadius: 12)
                }
                .padding(24)
            }
        }
        .background(Color.mfBackground)
        .task {
            await loadPresets()
            await loadServers()
        }
        .onChange(of: appState.droppedFilePath) { _, newPath in
            if let path = newPath {
                appState.droppedFilePath = nil
                Task { await selectFile(path) }
            }
        }
    }

    // MARK: - File Selection Panel

    private var fileSelectionPanel: some View {
        VStack(spacing: 16) {
            if let probe = probeResult {
                // File info display
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "film")
                            .font(.system(size: 16))
                            .foregroundColor(.mfPrimary)
                        Text(URL(fileURLWithPath: probe.filePath).lastPathComponent)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.mfTextPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button {
                            clearSelection()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.mfTextMuted)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(probe.filePath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.mfTextMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    // Media info grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                    ], spacing: 10) {
                        infoChip(label: "Resolution", value: probe.resolution ?? "--")
                        infoChip(label: "Codec", value: (probe.videoCodec ?? "--").uppercased())
                        infoChip(label: "Bitrate", value: probe.formattedBitrate)
                        infoChip(label: "Size", value: probe.formattedSize)
                        infoChip(label: "Duration", value: probe.formattedDuration)
                        infoChip(label: "Audio", value: audioDescription(probe))
                    }
                }
                .padding(16)
                .glassPanel(cornerRadius: 10)
            } else {
                // Drop zone
                VStack(spacing: 14) {
                    if isProbing {
                        ProgressView()
                            .scaleEffect(0.9)
                        Text("Analyzing file...")
                            .font(.system(size: 12))
                            .foregroundColor(.mfTextMuted)
                    } else {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 36))
                            .foregroundColor(.mfTextMuted)
                        Text("Select File or Drag & Drop")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.mfTextSecondary)
                        Text("MKV, MP4, AVI, MOV, TS, M4V, WEBM")
                            .font(.system(size: 11))
                            .foregroundColor(.mfTextMuted)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 200)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [8, 5]))
                        .foregroundColor(.mfGlassBorder)
                )
                .background(Color.mfGlass)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .onTapGesture {
                    openFilePicker()
                }
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers: providers)
                    return true
                }
            }

            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                    Text(error)
                        .font(.system(size: 11))
                }
                .foregroundColor(.mfError)
            }

            if let success = successMessage {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                    Text(success)
                        .font(.system(size: 11))
                }
                .foregroundColor(.mfSuccess)
            }
        }
    }

    // MARK: - Settings Panel

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Preset row
            if !presets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("PRESET")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                        .tracking(1)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets) { preset in
                                Button {
                                    applyPreset(preset)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: preset.iconName)
                                            .font(.system(size: 11))
                                        Text(preset.name)
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(selectedPreset?.id == preset.id ? Color.mfPrimary.opacity(0.2) : Color.mfSurfaceLight)
                                    .foregroundColor(selectedPreset?.id == preset.id ? .mfPrimary : .mfTextSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 7))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7)
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
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
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

                VStack(alignment: .leading, spacing: 6) {
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
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
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
                    .frame(width: 110)
                }

                VStack(alignment: .leading, spacing: 6) {
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

            // Quality control with bitrate mode toggle
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("QUALITY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                        .tracking(1)
                    Spacer()
                    Picker("", selection: $bitrateMode) {
                        Text("CRF").tag("crf")
                        Text("Bitrate").tag("vbr")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .onChange(of: bitrateMode) {
                        selectedPreset = nil
                    }
                }

                if bitrateMode == "crf" {
                    HStack {
                        Slider(value: $crfValue, in: 15...35, step: 1)
                            .tint(.mfPrimary)
                        Text("\(Int(crfValue))")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.mfTextPrimary)
                            .frame(width: 28, alignment: .trailing)
                    }
                    HStack {
                        Text("Higher quality")
                            .font(.system(size: 9))
                            .foregroundColor(.mfTextMuted)
                        Spacer()
                        Text("Smaller file")
                            .font(.system(size: 9))
                            .foregroundColor(.mfTextMuted)
                    }
                } else {
                    HStack {
                        Slider(value: $targetBitrateMbps, in: 1...50, step: 0.5)
                            .tint(.mfPrimary)
                        Text(String(format: "%.1f Mbps", targetBitrateMbps))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.mfTextPrimary)
                            .frame(width: 75, alignment: .trailing)
                    }
                    HStack {
                        Text("Lower bitrate")
                            .font(.system(size: 9))
                            .foregroundColor(.mfTextMuted)
                        Spacer()
                        Text("Higher bitrate")
                            .font(.system(size: 9))
                            .foregroundColor(.mfTextMuted)
                    }
                }
            }

            // Estimated output size
            if probeResult != nil, let sizeText = estimatedSizeText {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.zipper")
                            .font(.system(size: 11))
                            .foregroundColor(.mfTextMuted)
                        Text("EST. OUTPUT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.mfTextMuted)
                            .tracking(1)
                    }

                    Text(sizeText)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.mfPrimary)

                    if let reduction = estimatedReductionText {
                        Text(reduction)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(reduction.contains("smaller") ? .mfSuccess : .mfWarning)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background((reduction.contains("smaller") ? Color.mfSuccess : Color.mfWarning).opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    Spacer()
                }
                .padding(10)
                .background(Color.mfGlass)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfGlassBorder, lineWidth: 1))
            }

            // Server picker + Start button row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
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
                    .frame(width: 130)
                }

                Spacer()

                Button {
                    Task { await startTranscode() }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 12))
                        }
                        Text("Start Transcode")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
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
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(audioMode == value ? Color.mfPrimary.opacity(0.15) : Color.mfSurfaceLight)
        }
        .buttonStyle(.plain)
    }

    private func infoChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.mfTextMuted)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
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

    // MARK: - Size Estimation

    private var estimatedOutputBytes: Int? {
        guard let probe = probeResult, probe.durationSeconds > 0 else { return nil }

        if bitrateMode != "crf" {
            // Bitrate mode: precise calculation
            let videoBits = targetBitrateMbps * 1_000_000 * probe.durationSeconds
            let audioBits = 128_000.0 * probe.durationSeconds
            return Int((videoBits + audioBits) / 8)
        } else {
            // CRF mode: heuristic estimation
            guard let sourceBitrate = probe.bitrate, sourceBitrate > 0 else { return nil }
            let codecRatio = codecEfficiencyRatio(source: probe.videoCodec, target: videoCodec)
            let crfScale = crfScaleFactor(crf: crfValue)
            let resScale = resolutionScaleFactor(sourceResolution: probe.resolution)
            let estimatedBitrate = Double(sourceBitrate) * codecRatio * crfScale * resScale
            let totalBits = estimatedBitrate * probe.durationSeconds
            let audioBits = 128_000.0 * probe.durationSeconds
            return Int((totalBits + audioBits) / 8)
        }
    }

    private func codecEfficiencyRatio(source: String?, target: String) -> Double {
        let src = (source ?? "").lowercased()
        let isSourceH264 = src.contains("h264") || src.contains("264") || src.contains("avc")
        let isSourceHEVC = src.contains("hevc") || src.contains("h265") || src.contains("265")

        switch target {
        case "libx265":
            return isSourceH264 ? 0.65 : isSourceHEVC ? 0.85 : 0.70
        case "libsvtav1":
            return isSourceH264 ? 0.55 : isSourceHEVC ? 0.75 : 0.60
        case "libx264":
            return isSourceH264 ? 0.85 : 0.90
        default:
            return 0.85
        }
    }

    private func crfScaleFactor(crf: Double) -> Double {
        // Exponential curve: CRF 23 = 1.0, lower CRF = larger file, higher = smaller
        // Each CRF point ≈ 12% size change
        return pow(1.12, crf - 23)
    }

    private func resolutionScaleFactor(sourceResolution: String?) -> Double {
        guard targetResolution != "source" else { return 1.0 }
        guard let source = sourceResolution else { return 1.0 }
        let sourcePixels = pixelCount(from: source)
        let targetPixels = pixelCountForTarget(targetResolution)
        guard sourcePixels > 0, targetPixels > 0 else { return 1.0 }
        if targetPixels >= sourcePixels { return 1.0 }
        return Double(targetPixels) / Double(sourcePixels)
    }

    private func pixelCount(from resolution: String) -> Int {
        let parts = resolution.lowercased().split(separator: "x")
        guard parts.count == 2,
              let w = Int(parts[0]),
              let h = Int(parts[1]) else { return 0 }
        return w * h
    }

    private func pixelCountForTarget(_ target: String) -> Int {
        switch target {
        case "4K": return 3840 * 2160
        case "1080p": return 1920 * 1080
        case "720p": return 1280 * 720
        case "SD": return 720 * 480
        default: return 0
        }
    }

    private var estimatedSizeText: String? {
        guard let bytes = estimatedOutputBytes, bytes > 0 else { return nil }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "~%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "~%.0f MB", mb)
    }

    private var estimatedReductionText: String? {
        guard let bytes = estimatedOutputBytes, let probe = probeResult, probe.fileSize > 0 else { return nil }
        let reduction = 1.0 - (Double(bytes) / Double(probe.fileSize))
        if reduction > 0 {
            return String(format: "%.0f%% smaller", reduction * 100)
        } else {
            return String(format: "%.0f%% larger", abs(reduction) * 100)
        }
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
        successMessage = nil
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
        successMessage = nil
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
        successMessage = nil

        var config: [String: AnyCodable] = [
            "video_codec": AnyCodable(videoCodec),
            "container": AnyCodable(container),
            "bitrate_mode": AnyCodable(bitrateMode),
            "audio_mode": AnyCodable(audioMode),
        ]
        if bitrateMode == "crf" {
            config["crf_value"] = AnyCodable(Int(crfValue))
        } else {
            config["target_bitrate"] = AnyCodable("\(Int(targetBitrateMbps))M")
        }
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
            let fileName = URL(fileURLWithPath: probe.filePath).lastPathComponent
            selectedFilePath = nil
            probeResult = nil
            errorMessage = nil
            successMessage = "Job queued for \(fileName) — view in Processing queue"
            await viewModel.loadJobs()
            await viewModel.loadQueueStats()
        } catch {
            errorMessage = "Failed to start transcode: \(error.localizedDescription)"
        }
        isSubmitting = false
    }
}
