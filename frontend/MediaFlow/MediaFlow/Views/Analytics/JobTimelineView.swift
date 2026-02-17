import SwiftUI

struct JobTimelineView: View {
    let data: JobTimelineResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Job Timeline")
                .font(.system(size: 16, weight: .bold))

            Text("Visual timeline of transcode jobs across workers")
                .font(.system(size: 12))
                .foregroundColor(.mfTextSecondary)

            if data.jobs.isEmpty {
                Text("No job data available for this period")
                    .font(.system(size: 12))
                    .foregroundColor(.mfTextMuted)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(data.workers) { worker in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(worker.name)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.mfTextSecondary)
                                    .padding(.top, 8)

                                let workerJobs = data.jobs.filter { $0.workerId == worker.id }

                                if workerJobs.isEmpty {
                                    HStack {
                                        Text("No jobs")
                                            .font(.system(size: 10))
                                            .foregroundColor(.mfTextMuted)
                                    }
                                    .frame(height: 28)
                                } else {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 3) {
                                            ForEach(workerJobs) { job in
                                                TimelineJobBar(job: job)
                                            }
                                        }
                                    }
                                }

                                Divider().background(Color.mfGlassBorder)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct TimelineJobBar: View {
    let job: JobTimelineEntry
    @State private var isHovered = false

    private var statusColor: Color {
        switch job.status {
        case "completed": return .mfSuccess
        case "transcoding": return .mfPrimary
        case "failed": return .mfError
        case "queued": return .mfTextMuted
        default: return .mfWarning
        }
    }

    private var barWidth: CGFloat {
        let duration = job.durationSeconds ?? 60
        return max(30, min(200, CGFloat(duration / 60) * 3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(job.title)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            if let dur = job.durationSeconds {
                Text(formatDuration(dur))
                    .font(.system(size: 7))
                    .foregroundColor(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: barWidth, alignment: .leading)
        .background(statusColor.opacity(isHovered ? 0.9 : 0.7))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { isHovered = $0 }
        .help("\(job.title)\nStatus: \(job.status)\nCodec: \(job.sourceCodec ?? "?") → \(job.targetCodec ?? "?")\nDuration: \(formatDuration(job.durationSeconds ?? 0))")
    }

    private func formatDuration(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        if m > 60 { return "\(m / 60)h \(m % 60)m" }
        return "\(m)m \(s)s"
    }
}
