import SwiftUI
import AppKit

struct TranscodeJobCardView: View {
    let job: TranscodeJob
    var logMessages: [String] = []
    var transferProgress: TransferProgress?
    var phaseLabel: String? = nil
    var onCancel: (() -> Void)? = nil
    @State private var showLog: Bool = false

    private var sizeChangeColor: Color {
        guard let reduction = job.sizeReductionPercent else { return .mfSuccess }
        return reduction >= 0 ? .mfSuccess : .mfWarning
    }

    private var statusColor: Color {
        switch job.status {
        case "completed": return .mfSuccess
        case "failed": return .mfError
        default: return .mfPrimary
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.mfSurfaceLight)
            .frame(width: 160, height: 96)
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 20))
                    .foregroundColor(.mfTextMuted.opacity(0.5))
            )
    }

    private var phaseDescription: String? {
        if job.status == "transferring", let tp = transferProgress {
            let dir = tp.label.isEmpty
                ? (tp.direction == "download" ? "Downloading" : "Uploading")
                : tp.label
            return "\(dir) — \(tp.speed) — ETA \(tp.formattedETA)"
        }
        switch job.status {
        case "transferring": return phaseLabel ?? "Transferring file..."
        case "verifying": return "Verifying output..."
        case "replacing": return "Replacing original..."
        default: return phaseLabel
        }
    }

    private var transferStatusLabel: String {
        if let tp = transferProgress, !tp.label.isEmpty {
            return tp.label
        }
        if let label = phaseLabel {
            return label
        }
        return job.statusDisplayName
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail
                ZStack(alignment: .bottomTrailing) {
                    if let mediaItemId = job.mediaItemId {
                        AsyncImage(url: URL(string: "http://localhost:9876/api/library/thumb/\(mediaItemId)")) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure:
                                thumbnailPlaceholder
                            case .empty:
                                thumbnailPlaceholder
                                    .overlay(ProgressView().scaleEffect(0.5))
                            @unknown default:
                                thumbnailPlaceholder
                            }
                        }
                        .frame(width: 160, height: 96)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        thumbnailPlaceholder
                    }

                    // Status badge overlay
                    if job.status == "completed" || job.status == "failed" {
                        Image(systemName: job.status == "completed" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(job.status == "completed" ? .mfSuccess : .mfError)
                            .padding(4)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .padding(4)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    // Title row
                    HStack {
                        Text(job.mediaTitle ?? "Unknown")
                            .font(.system(size: 16, weight: .bold))
                            .lineLimit(1)

                        Spacer()

                        if job.status == "completed" {
                            Text("DONE")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.mfSuccess)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.mfSuccess.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        if job.status == "failed" {
                            Text("FAILED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.mfError)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.mfError.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        // Log toggle
                        if job.isActive || job.status == "transferring" || !logMessages.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showLog.toggle() }
                            } label: {
                                Image(systemName: "terminal")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(showLog ? .mfPrimary : .mfTextMuted)
                                    .padding(6)
                                    .background(showLog ? Color.mfPrimary.opacity(0.1) : Color.mfSurface.opacity(0.5))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }

                        if let onCancel = onCancel, (job.isActive || job.status == "queued" || job.status == "transferring") {
                            Button(action: onCancel) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.mfError)
                                    .padding(6)
                                    .background(Color.mfError.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Spec line
                    HStack(spacing: 4) {
                        Text(job.sourcePath?.components(separatedBy: "/").last ?? "source")
                            .font(.mfMonoSmall)
                            .foregroundColor(.mfTextMuted)
                        if job.isActive || job.status == "queued" || job.status == "transferring" {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.mfTextMuted)
                            Text(phaseDescription ?? "Processing...")
                                .font(.mfMonoSmall)
                                .foregroundColor(.mfPrimary)
                        }
                    }

                    Spacer(minLength: 8)

                    // Stats + Progress
                    if job.status == "completed" {
                        // Completion stats
                        HStack(spacing: 0) {
                            StatChip(label: "BEFORE", value: job.formattedSourceSize)
                            Divider().frame(height: 24).padding(.horizontal, 8)
                            StatChip(label: "AFTER", value: job.formattedOutputSize, color: sizeChangeColor)
                            Divider().frame(height: 24).padding(.horizontal, 8)
                            if let reduction = job.sizeReductionPercent {
                                StatChip(
                                    label: reduction >= 0 ? "SAVED" : "LARGER",
                                    value: String(format: "%.1f%%", abs(reduction)),
                                    color: reduction >= 0 ? .mfSuccess : .mfWarning
                                )
                                Divider().frame(height: 24).padding(.horizontal, 8)
                            }
                            StatChip(label: "DURATION", value: job.formattedDuration)
                            if job.cloudCostUsd != nil {
                                Divider().frame(height: 24).padding(.horizontal, 8)
                                StatChip(label: "GPU COST", value: job.formattedCloudCost, color: .mfPrimary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.mfSurface.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        HStack(spacing: 12) {
                            if job.status == "transferring", let tp = transferProgress {
                                // Transfer speed/ETA chips
                                HStack(spacing: 0) {
                                    StatChip(label: "SPEED", value: tp.speed)
                                    Divider().frame(height: 24).padding(.horizontal, 8)
                                    StatChip(label: "ETA", value: tp.formattedETA)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.mfSurface.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else if job.isActive {
                                // Transcode speed/ETA chips
                                HStack(spacing: 0) {
                                    StatChip(label: "SPEED", value: job.currentFps.map { String(format: "%.1f FPS", $0) } ?? "--")
                                    Divider().frame(height: 24).padding(.horizontal, 8)
                                    StatChip(label: "ETA", value: job.formattedETA)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.mfSurface.opacity(0.5))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            // Progress bar
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(job.status == "transferring" ? transferStatusLabel : job.statusDisplayName)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(statusColor)
                                        .lineLimit(1)
                                    Spacer()
                                    if job.status == "transferring", let tp = transferProgress {
                                        Text("\(Int(tp.progress))%")
                                            .font(.mfMonoSmall)
                                            .foregroundColor(.mfTextSecondary)
                                    } else if job.status != "failed" {
                                        Text("\(Int(job.progressPercent))%")
                                            .font(.mfMonoSmall)
                                            .foregroundColor(.mfTextSecondary)
                                    }
                                }

                                if job.status == "failed" {
                                    if let log = job.ffmpegLog, !log.isEmpty {
                                        let errorLine = log.components(separatedBy: "\n").last(where: { !$0.isEmpty }) ?? log
                                        Text(errorLine)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(.mfError.opacity(0.8))
                                            .lineLimit(2)
                                    }
                                } else if job.status == "transferring" {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.mfSurface)
                                                .frame(height: 6)
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.mfPrimary)
                                                .frame(width: geo.size.width * (transferProgress?.progress ?? 0) / 100.0, height: 6)
                                                .animation(.linear(duration: 0.3), value: transferProgress?.progress)
                                        }
                                    }
                                    .frame(height: 6)
                                } else {
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.mfSurface)
                                                .frame(height: 6)
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.mfPrimary)
                                                .frame(width: geo.size.width * job.progressPercent / 100.0, height: 6)
                                        }
                                    }
                                    .frame(height: 6)
                                }
                            }
                            .frame(minWidth: 200)
                        }
                    }
                }
            }
            .padding(16)

            // Collapsible log panel
            if showLog && !logMessages.isEmpty {
                Divider().opacity(0.3)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(logMessages.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.mfTextSecondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 120)
                    .background(Color.black.opacity(0.2))
                    .onChange(of: logMessages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(logMessages.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .background(
            job.status == "completed"
            ? Color.mfSuccess.opacity(0.03)
            : job.status == "failed"
            ? Color.mfError.opacity(0.03)
            : Color.mfSurface
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    job.status == "completed"
                    ? Color.mfSuccess.opacity(0.2)
                    : job.status == "failed"
                    ? Color.mfError.opacity(0.2)
                    : Color.mfPrimary.opacity(0.1),
                    lineWidth: 1
                )
        )
        .contextMenu {
            if let cmd = job.ffmpegCommand {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(cmd, forType: .string)
                } label: {
                    Label("Copy FFmpeg Command", systemImage: "terminal")
                }
            }
            if let log = job.ffmpegLog, !log.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(log, forType: .string)
                } label: {
                    Label("Copy Log", systemImage: "doc.text")
                }
            }
            if job.status == "transcoding" || job.status == "queued" || job.status == "transferring" {
                Divider()
                Button(role: .destructive) {
                    onCancel?()
                } label: {
                    Label("Cancel Job", systemImage: "xmark.circle")
                }
            }
        }
    }
}

struct StatChip: View {
    let label: String
    let value: String
    var color: Color = .mfSuccess

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.mfTextMuted)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }
}
