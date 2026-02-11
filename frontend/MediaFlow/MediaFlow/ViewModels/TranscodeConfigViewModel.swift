import SwiftUI
import Combine

@MainActor
class TranscodeConfigViewModel: ObservableObject {
    @Published var presets: [TranscodePreset] = []
    @Published var selectedPreset: TranscodePreset?
    @Published var videoCodec: String = "libx265"
    @Published var container: String = "mkv"
    @Published var targetResolution: String? = nil
    @Published var bitrateMode: String = "crf"
    @Published var crfValue: Double = 22
    @Published var targetBitrate: Double = 12.5
    @Published var audioMode: String = "copy"
    @Published var audioCodec: String = "aac"
    @Published var subtitleMode: String = "copy"
    @Published var hdrMode: String = "preserve"
    @Published var hwAccel: Bool = false
    @Published var twoPass: Bool = false
    @Published var isLoading: Bool = false
    @Published var estimatedSize: Int?
    @Published var estimatedReduction: Double?
    @Published var availableServers: [ServerPickerItem] = []
    @Published var selectedServerId: Int?  // nil = auto

    private let service: BackendService
    private var cancellables = Set<AnyCancellable>()
    var mediaItems: [MediaItem] = [] {
        didSet { updateEstimates() }
    }

    init(service: BackendService = BackendService()) {
        self.service = service

        Publishers.CombineLatest4($targetBitrate, $videoCodec, $targetResolution, $container)
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateEstimates()
            }
            .store(in: &cancellables)
    }

    func updateEstimates() {
        let totalDurationMs = mediaItems.reduce(0) { $0 + ($1.durationMs ?? 0) }
        let totalDurationSec = Double(totalDurationMs) / 1000.0
        let sourceTotal = totalSourceSize
        guard totalDurationSec > 0, sourceTotal > 0 else { return }

        // Video bytes = bitrate (Mbps -> bits/sec) * duration / 8
        let videoBitsPerSec = targetBitrate * 1_000_000
        let videoBytes = (videoBitsPerSec * totalDurationSec) / 8.0

        // Estimate audio at ~192 kbps
        let audioBytes = (192_000.0 * totalDurationSec) / 8.0

        let estimated = Int(videoBytes + audioBytes)
        estimatedSize = estimated

        let ratio = Double(estimated) / Double(sourceTotal)
        estimatedReduction = max(0, (1.0 - ratio) * 100)
    }

    func loadPresets() async {
        do {
            presets = try await service.getPresets()
        } catch {
            print("Failed to load presets: \(error)")
        }
    }

    func loadAvailableServers() async {
        do {
            availableServers = try await service.getAvailableServers()
        } catch {
            print("Failed to load available servers: \(error)")
        }
    }

    func applyPreset(_ preset: TranscodePreset) {
        selectedPreset = preset
        videoCodec = preset.videoCodec
        container = preset.container
        targetResolution = preset.targetResolution
        bitrateMode = preset.bitrateMode
        crfValue = Double(preset.crfValue ?? 22)
        audioMode = preset.audioMode
        audioCodec = preset.audioCodec ?? "aac"
        subtitleMode = preset.subtitleMode
        hdrMode = preset.hdrMode
        twoPass = preset.twoPass
    }

    func queueJobs() async -> Bool {
        isLoading = true
        defer { isLoading = false }

        var request = TranscodeJobCreateRequest(
            mediaItemIds: mediaItems.map(\.id),
            presetId: selectedPreset?.id,
            priority: 0
        )
        request.preferredWorkerId = selectedServerId

        do {
            let _ = try await service.createTranscodeJobs(request: request)
            return true
        } catch {
            print("Failed to create jobs: \(error)")
            return false
        }
    }

    func startNow() async -> Bool {
        isLoading = true
        defer { isLoading = false }

        var request = TranscodeJobCreateRequest(
            mediaItemIds: mediaItems.map(\.id),
            presetId: selectedPreset?.id,
            priority: 10
        )
        request.preferredWorkerId = selectedServerId

        do {
            let _ = try await service.createTranscodeJobs(request: request)
            return true
        } catch {
            print("Failed to start jobs: \(error)")
            return false
        }
    }

    var totalSourceSize: Int {
        mediaItems.reduce(0) { $0 + ($1.fileSize ?? 0) }
    }

    var sourceItem: MediaItem? {
        mediaItems.first
    }
}
