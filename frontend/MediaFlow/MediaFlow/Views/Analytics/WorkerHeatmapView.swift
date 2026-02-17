import SwiftUI

struct WorkerHeatmapView: View {
    let data: WorkerHeatmapResponse

    private let hours = Array(0..<24)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Worker Performance Heatmap")
                .font(.system(size: 16, weight: .bold))

            Text("FPS by worker and hour of day")
                .font(.system(size: 12))
                .foregroundColor(.mfTextSecondary)

            if data.workers.isEmpty {
                Text("No worker data available")
                    .font(.system(size: 12))
                    .foregroundColor(.mfTextMuted)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        // Hour labels
                        HStack(spacing: 2) {
                            Text("")
                                .frame(width: 80)
                            ForEach(hours, id: \.self) { hour in
                                Text("\(hour)")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(.mfTextMuted)
                                    .frame(width: 24, height: 16)
                            }
                        }

                        // Worker rows
                        ForEach(data.workers) { worker in
                            HStack(spacing: 2) {
                                Text(worker.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.mfTextSecondary)
                                    .frame(width: 80, alignment: .leading)
                                    .lineLimit(1)

                                ForEach(hours, id: \.self) { hour in
                                    let entry = data.entries.first(where: { $0.workerId == worker.id && $0.hour == hour })
                                    let fps = entry?.avgFps ?? 0
                                    let maxFps = data.entries.map(\.avgFps).max() ?? 1
                                    let intensity = maxFps > 0 ? fps / maxFps : 0

                                    Rectangle()
                                        .fill(heatColor(intensity: intensity))
                                        .frame(width: 24, height: 24)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                        .help("\(worker.name) at \(hour):00 — \(String(format: "%.1f", fps)) FPS, \(entry?.jobCount ?? 0) jobs")
                                }
                            }
                        }
                    }
                }

                // Legend
                HStack(spacing: 12) {
                    Text("Low")
                        .font(.system(size: 9))
                        .foregroundColor(.mfTextMuted)
                    HStack(spacing: 1) {
                        ForEach(0..<5) { i in
                            Rectangle()
                                .fill(heatColor(intensity: Double(i) / 4.0))
                                .frame(width: 16, height: 10)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    Text("High")
                        .font(.system(size: 9))
                        .foregroundColor(.mfTextMuted)
                }
            }
        }
        .padding(16)
        .background(Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func heatColor(intensity: Double) -> Color {
        if intensity <= 0 { return Color.mfSurfaceLight }
        if intensity < 0.25 { return Color.mfPrimary.opacity(0.2) }
        if intensity < 0.5 { return Color.mfPrimary.opacity(0.4) }
        if intensity < 0.75 { return Color.mfSuccess.opacity(0.6) }
        return Color.mfSuccess.opacity(0.9)
    }
}
