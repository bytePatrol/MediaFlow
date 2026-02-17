import SwiftUI

struct MediaItemDetailView: View {
    let item: MediaItem
    var onTranscode: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    @State private var transcodeHistory: [TranscodeJob] = []
    @State private var recommendations: [Recommendation] = []
    @State private var isLoadingDetails = false

    private let service = BackendService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 18, weight: .bold))
                    if let year = item.year {
                        Text(String(year))
                            .font(.system(size: 13))
                            .foregroundColor(.mfTextSecondary)
                    }
                }
                Spacer()
                if let onDismiss = onDismiss {
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.mfTextMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(Color.mfSurface)

            Divider().background(Color.mfGlassBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Video section
                    DetailSection(title: "Video", icon: "film") {
                        DetailRow(label: "Codec", value: item.codecDisplayName)
                        DetailRow(label: "Resolution", value: item.resolutionBadgeText)
                        if let w = item.width, let h = item.height {
                            DetailRow(label: "Dimensions", value: "\(w) × \(h)")
                        }
                        DetailRow(label: "Bitrate", value: item.videoBitrate?.formattedBitrate ?? "--")
                        if let fps = item.frameRate {
                            DetailRow(label: "Frame Rate", value: String(format: "%.2f fps", fps))
                        }
                        if let depth = item.bitDepth {
                            DetailRow(label: "Bit Depth", value: "\(depth)-bit")
                        }
                        if item.isHdr {
                            DetailRow(label: "HDR", value: item.hdrFormat ?? "HDR")
                        }
                    }

                    // Audio section
                    DetailSection(title: "Audio", icon: "speaker.wave.3") {
                        DetailRow(label: "Codec", value: item.audioDisplayName)
                        if let channels = item.audioChannels {
                            DetailRow(label: "Channels", value: "\(channels)")
                        }
                        if let layout = item.audioChannelLayout {
                            DetailRow(label: "Layout", value: layout)
                        }
                        DetailRow(label: "Bitrate", value: item.audioBitrate?.formattedBitrate ?? "--")
                    }

                    // File section
                    DetailSection(title: "File", icon: "doc") {
                        DetailRow(label: "Size", value: item.formattedFileSize)
                        DetailRow(label: "Container", value: (item.container ?? "--").uppercased())
                        DetailRow(label: "Duration", value: item.formattedDuration)
                        if let path = item.filePath {
                            DetailRow(label: "Path", value: path)
                        }
                    }

                    // Metadata section
                    DetailSection(title: "Metadata", icon: "info.circle") {
                        DetailRow(label: "Play Count", value: "\(item.playCount)")
                        if let genres = item.genres, !genres.isEmpty {
                            DetailRow(label: "Genres", value: genres.joined(separator: ", "))
                        }
                        if let directors = item.directors, !directors.isEmpty {
                            DetailRow(label: "Directors", value: directors.joined(separator: ", "))
                        }
                    }

                    // Transcode History section
                    transcodeHistorySection

                    // Recommendation Status section
                    recommendationStatusSection

                    // Quick actions
                    if let onTranscode = onTranscode {
                        Button {
                            onTranscode()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt")
                                Text("Quick Transcode")
                            }
                            .primaryButton()
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 380)
        .background(Color.mfBackground)
        .task { await loadDetails() }
    }

    // MARK: - Load Details

    private func loadDetails() async {
        isLoadingDetails = true
        async let jobsTask: () = loadTranscodeHistory()
        async let recsTask: () = loadRecommendations()
        _ = await (jobsTask, recsTask)
        isLoadingDetails = false
    }

    private func loadTranscodeHistory() async {
        do {
            let response = try await service.getTranscodeJobs(mediaItemId: item.id)
            transcodeHistory = response.items
        } catch {
            // Non-critical, leave empty
        }
    }

    private func loadRecommendations() async {
        do {
            let allRecs = try await service.getRecommendations()
            recommendations = allRecs.filter { $0.mediaItemId == item.id }
        } catch {
            // Non-critical, leave empty
        }
    }

    // MARK: - Transcode History Section

    @ViewBuilder
    private var transcodeHistorySection: some View {
        DetailSection(title: "Transcode History", icon: "clock.arrow.circlepath") {
            if isLoadingDetails {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else if transcodeHistory.isEmpty {
                Text("No transcode history")
                    .font(.system(size: 11))
                    .foregroundColor(.mfTextMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                ForEach(transcodeHistory) { job in
                    transcodeJobRow(job)
                    if job.id != transcodeHistory.last?.id {
                        Divider().background(Color.mfGlassBorder.opacity(0.5))
                    }
                }
            }
        }
    }

    private func transcodeJobRow(_ job: TranscodeJob) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: jobStatusIcon(job.status))
                    .font(.system(size: 10))
                    .foregroundColor(jobStatusColor(job.status))
                if let codec = job.configJson?["video_codec"]?.stringValue {
                    Text(codec.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.mfPrimary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text(job.statusDisplayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(jobStatusColor(job.status))
                Spacer()
                if let date = job.completedAt ?? job.createdAt {
                    Text(formatJobDate(date))
                        .font(.system(size: 9))
                        .foregroundColor(.mfTextMuted)
                }
            }
            HStack(spacing: 12) {
                if let reduction = job.sizeReductionPercent {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.right")
                            .font(.system(size: 8))
                        Text(String(format: "%.1f%% smaller", reduction))
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.mfSuccess)
                }
                if let vmaf = job.vmafScore {
                    HStack(spacing: 3) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 8))
                        Text(String(format: "VMAF %.1f", vmaf))
                            .font(.system(size: 10))
                    }
                    .foregroundColor(colorForName(job.vmafColor))
                }
                if let srcSize = job.sourceSize, let outSize = job.outputSize {
                    Text("\(formatJobBytes(srcSize)) -> \(formatJobBytes(outSize))")
                        .font(.system(size: 10))
                        .foregroundColor(.mfTextMuted)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func jobStatusIcon(_ status: String) -> String {
        switch status {
        case "completed": return "checkmark.circle.fill"
        case "failed": return "xmark.circle.fill"
        case "cancelled": return "slash.circle.fill"
        case "transcoding", "transferring", "verifying", "replacing": return "arrow.triangle.2.circlepath"
        case "queued": return "clock.fill"
        case "paused": return "pause.circle.fill"
        default: return "circle"
        }
    }

    private func jobStatusColor(_ status: String) -> Color {
        switch status {
        case "completed": return .mfSuccess
        case "failed": return .mfError
        case "cancelled": return .mfTextMuted
        case "transcoding", "transferring", "verifying", "replacing": return .mfPrimary
        case "queued": return .mfWarning
        default: return .mfTextSecondary
        }
    }

    private func formatJobDate(_ isoDate: String) -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fmt.date(from: isoDate) else { return isoDate.prefix(10).description }
        let display = DateFormatter()
        display.dateStyle = .short
        display.timeStyle = .short
        return display.string(from: date)
    }

    private func formatJobBytes(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", mb)
    }

    // MARK: - Recommendation Status Section

    @ViewBuilder
    private var recommendationStatusSection: some View {
        DetailSection(title: "Recommendations", icon: "lightbulb") {
            if isLoadingDetails {
                HStack {
                    Spacer()
                    ProgressView()
                        .controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 4)
            } else if recommendations.isEmpty {
                Text("No recommendations")
                    .font(.system(size: 11))
                    .foregroundColor(.mfTextMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 4)
            } else {
                ForEach(recommendations) { rec in
                    recommendationRow(rec)
                    if rec.id != recommendations.last?.id {
                        Divider().background(Color.mfGlassBorder.opacity(0.5))
                    }
                }
            }
        }
    }

    private func recommendationRow(_ rec: Recommendation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: rec.typeIcon)
                    .font(.system(size: 10))
                    .foregroundColor(colorForName(rec.severityColor))
                Text(rec.typeDisplayName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(colorForName(rec.severityColor).opacity(0.3))
                    .clipShape(Capsule())
                Spacer()
                Text(recStatusLabel(rec))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(recStatusColor(rec))
            }
            Text(rec.title)
                .font(.system(size: 11))
                .foregroundColor(.mfTextSecondary)
                .lineLimit(2)
            if let savings = rec.estimatedSavings, savings > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 8))
                    Text("~\(savings.formattedFileSize) estimated savings")
                        .font(.system(size: 10))
                }
                .foregroundColor(.mfSuccess)
            }
        }
        .padding(.vertical, 2)
    }

    private func recStatusLabel(_ rec: Recommendation) -> String {
        if rec.isDismissed { return "Dismissed" }
        if rec.isActioned { return "Queued" }
        return "Pending"
    }

    private func recStatusColor(_ rec: Recommendation) -> Color {
        if rec.isDismissed { return .mfTextMuted }
        if rec.isActioned { return .mfPrimary }
        return .mfWarning
    }

    private func colorForName(_ name: String) -> Color {
        switch name {
        case "mfSuccess": return .mfSuccess
        case "mfWarning": return .mfWarning
        case "mfError": return .mfError
        case "mfInfo": return .mfInfo
        case "mfPrimary": return .mfPrimary
        case "mfTextMuted": return .mfTextMuted
        case "mfTextSecondary": return .mfTextSecondary
        default: return .mfTextMuted
        }
    }
}

struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(.mfPrimary)
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.mfTextPrimary)
            }

            VStack(alignment: .leading, spacing: 6) {
                content
            }
            .padding(12)
            .background(Color.mfSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.mfTextMuted)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .foregroundColor(.mfTextSecondary)
                .lineLimit(2)
            Spacer()
        }
    }
}
