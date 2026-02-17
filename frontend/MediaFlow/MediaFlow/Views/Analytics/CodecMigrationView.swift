import SwiftUI
import Charts

struct CodecMigrationView: View {
    let data: CodecMigrationResponse

    private let codecColors: [String: Color] = [
        "hevc": .mfSuccess, "h265": .mfSuccess,
        "av1": .mfInfo,
        "h264": .mfWarning,
        "mpeg4": .mfError, "mpeg2video": .mfError,
        "vc1": .orange,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Codec Migration Progress")
                        .font(.system(size: 16, weight: .bold))
                    Text(String(format: "%.1f%% modern codecs (HEVC/AV1)", data.modernPct))
                        .font(.system(size: 12))
                        .foregroundColor(.mfSuccess)
                }
                Spacer()
                Text(String(format: "%.0f%%", data.modernPct))
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(.mfSuccess)
            }
            .padding(16)
            .background(Color.mfSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Stacked progress bar
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Distribution")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.mfTextSecondary)

                GeometryReader { geo in
                    HStack(spacing: 1) {
                        let sorted = data.current.sorted(by: { $0.value > $1.value })
                        let total = max(1, data.totalItems)
                        ForEach(sorted, id: \.key) { codec, count in
                            let width = geo.size.width * (Double(count) / Double(total))
                            Rectangle()
                                .fill(colorForCodec(codec))
                                .frame(width: max(2, width))
                                .help("\(codec.uppercased()): \(count) items (\(String(format: "%.1f%%", Double(count) / Double(total) * 100)))")
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(height: 24)

                // Legend
                HStack(spacing: 12) {
                    ForEach(data.current.sorted(by: { $0.value > $1.value }), id: \.key) { codec, count in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(colorForCodec(codec))
                                .frame(width: 8, height: 8)
                            Text("\(codec.uppercased()) (\(count))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.mfTextSecondary)
                        }
                    }
                }
            }
            .padding(16)
            .background(Color.mfSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // History chart
            if data.history.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Migration Timeline")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.mfTextSecondary)

                    Chart {
                        ForEach(data.history) { entry in
                            LineMark(
                                x: .value("Date", entry.date),
                                y: .value("Modern %", entry.modernCodecPct)
                            )
                            .foregroundStyle(Color.mfSuccess)

                            AreaMark(
                                x: .value("Date", entry.date),
                                y: .value("Modern %", entry.modernCodecPct)
                            )
                            .foregroundStyle(Color.mfSuccess.opacity(0.1))
                        }
                    }
                    .frame(height: 120)
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(Color.mfGlassBorder)
                            AxisValueLabel {
                                Text("\(value.as(Int.self) ?? 0)%")
                                    .font(.system(size: 9))
                                    .foregroundColor(.mfTextMuted)
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                Text(value.as(String.self) ?? "")
                                    .font(.system(size: 8))
                                    .foregroundColor(.mfTextMuted)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color.mfSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func colorForCodec(_ codec: String) -> Color {
        codecColors[codec.lowercased()] ?? .mfTextMuted
    }
}
