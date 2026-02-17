import SwiftUI
import AppKit

@MainActor
class ComparisonViewModel: ObservableObject {
    @Published var thumbnails: [ComparisonThumbnail] = []
    @Published var metadata: ComparisonMetadata?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = BackendService()

    func load(jobId: Int) async {
        isLoading = true
        errorMessage = nil

        // Load metadata and thumbnails in parallel
        async let metaTask: () = loadMetadata(jobId: jobId)
        async let thumbTask: () = loadThumbnails(jobId: jobId)
        _ = await (metaTask, thumbTask)

        isLoading = false
    }

    private func loadMetadata(jobId: Int) async {
        do {
            metadata = try await service.getComparisonMetadata(jobId: jobId)
        } catch {
            print("Failed to load comparison metadata: \(error)")
        }
    }

    private func loadThumbnails(jobId: Int) async {
        do {
            let response = try await service.getComparisonThumbnails(jobId: jobId)
            thumbnails = response.thumbnails
        } catch {
            errorMessage = "Failed to load thumbnails: \(error.localizedDescription)"
            print("Failed to load comparison thumbnails: \(error)")
        }
    }
}

struct ComparisonView: View {
    let jobId: Int
    @StateObject private var viewModel = ComparisonViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            headerBar

            Divider().overlay(Color.mfGlassBorder)

            if viewModel.isLoading {
                loadingState
            } else if let error = viewModel.errorMessage, viewModel.thumbnails.isEmpty {
                errorState(error)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Metadata comparison panel
                        if let meta = viewModel.metadata {
                            metadataPanel(meta)
                        }

                        // Thumbnail pairs
                        if !viewModel.thumbnails.isEmpty {
                            thumbnailSection
                        }
                    }
                    .padding(20)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color.mfBackground)
        .task {
            await viewModel.load(jobId: jobId)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Visual A/B Comparison")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.mfTextPrimary)
                Text("Job #\(jobId) - Original vs. Transcoded")
                    .font(.system(size: 12))
                    .foregroundColor(.mfTextSecondary)
            }
            Spacer()

            if let meta = viewModel.metadata, let vmaf = meta.vmafScore {
                VStack(spacing: 2) {
                    Text(String(format: "%.1f", vmaf))
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(vmafColor(vmaf))
                    Text("VMAF")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.mfTextMuted)
                }
                .frame(width: 60, height: 50)
                .background(vmafColor(vmaf).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.mfTextMuted)
                    .frame(width: 28, height: 28)
                    .background(Color.mfSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.mfSurface.opacity(0.5))
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Generating thumbnails...")
                .font(.system(size: 14))
                .foregroundColor(.mfTextSecondary)
            Text("This may take a moment for longer videos")
                .font(.system(size: 12))
                .foregroundColor(.mfTextMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundColor(.mfError)
            Text("Comparison Unavailable")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.mfTextPrimary)
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.mfTextSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Metadata Panel

    private func metadataPanel(_ meta: ComparisonMetadata) -> some View {
        HStack(spacing: 0) {
            // Original side
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.mfTextMuted)
                        .frame(width: 8, height: 8)
                    Text("ORIGINAL")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                        .tracking(1)
                }

                HStack(spacing: 16) {
                    metaItem(label: "Codec", value: meta.sourceCodec?.uppercased() ?? "--")
                    metaItem(label: "Resolution", value: meta.sourceResolution ?? "--")
                    metaItem(label: "Size", value: formatBytes(meta.sourceSize))
                    if let bitrate = meta.sourceBitrate {
                        metaItem(label: "Bitrate", value: formatBitrate(bitrate))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Divider with arrow
            VStack {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.mfPrimary)
            }
            .frame(width: 40)

            // Transcoded side
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.mfSuccess)
                        .frame(width: 8, height: 8)
                    Text("TRANSCODED")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.mfSuccess)
                        .tracking(1)
                }

                HStack(spacing: 16) {
                    metaItem(label: "Codec", value: meta.targetCodec?.uppercased() ?? "--", color: .mfSuccess)
                    metaItem(label: "Resolution", value: meta.targetResolution ?? "--", color: .mfSuccess)
                    metaItem(label: "Size", value: formatBytes(meta.targetSize), color: .mfSuccess)
                    if let reduction = meta.sizeReduction {
                        metaItem(
                            label: "Saved",
                            value: String(format: "%.1f%%", abs(reduction)),
                            color: reduction >= 0 ? .mfSuccess : .mfWarning
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.mfGlassBorder, lineWidth: 1)
        )
    }

    private func metaItem(label: String, value: String, color: Color = .mfTextPrimary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.mfTextMuted)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    // MARK: - Thumbnail Section

    private var thumbnailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Text("Frame Comparison")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.mfTextPrimary)
                Spacer()
                Text("\(viewModel.thumbnails.count) samples")
                    .font(.system(size: 12))
                    .foregroundColor(.mfTextMuted)
            }

            // Thumbnail pairs
            ForEach(viewModel.thumbnails) { thumb in
                thumbnailPair(thumb)
            }
        }
    }

    private func thumbnailPair(_ thumb: ComparisonThumbnail) -> some View {
        VStack(spacing: 0) {
            // Timestamp header
            HStack {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(.mfTextMuted)
                Text(thumb.timestamp)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.mfTextSecondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.mfSurface.opacity(0.7))

            // Side by side images
            HStack(spacing: 1) {
                // Original
                VStack(spacing: 4) {
                    thumbnailImage(base64: thumb.original)
                    Text("Original")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.mfTextMuted)
                }
                .frame(maxWidth: .infinity)

                // Transcoded
                VStack(spacing: 4) {
                    thumbnailImage(base64: thumb.transcoded)
                    Text("Transcoded")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.mfSuccess)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(8)
        }
        .background(Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.mfGlassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func thumbnailImage(base64: String) -> some View {
        if let data = Data(base64Encoded: base64),
           let nsImage = NSImage(data: data) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.mfSurfaceLight)
                .aspectRatio(16/9, contentMode: .fit)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundColor(.mfTextMuted.opacity(0.3))
                )
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int?) -> String {
        guard let bytes = bytes else { return "--" }
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.2f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    private func formatBitrate(_ bitrate: Int) -> String {
        let mbps = Double(bitrate) / 1_000_000
        if mbps >= 1 { return String(format: "%.1f Mbps", mbps) }
        let kbps = Double(bitrate) / 1_000
        return String(format: "%.0f Kbps", kbps)
    }

    private func vmafColor(_ score: Double) -> Color {
        if score >= 90 { return .mfSuccess }
        if score >= 80 { return .mfInfo }
        if score >= 70 { return .mfWarning }
        return .mfError
    }
}
