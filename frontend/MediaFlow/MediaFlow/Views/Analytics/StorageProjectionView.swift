import SwiftUI
import Charts

struct StorageProjectionView: View {
    let data: StorageSavingsProjection

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage Savings Projection")
                        .font(.system(size: 16, weight: .bold))
                    Text("Predicted savings over the next 12 months")
                        .font(.system(size: 12))
                        .foregroundColor(.mfTextSecondary)
                }
                Spacer()
            }

            // KPIs
            HStack(spacing: 12) {
                ProjectionKPI(title: "Current Size", value: data.currentTotalSize.formattedFileSize, color: .mfTextPrimary)
                ProjectionKPI(title: "If Optimized", value: data.ifAllOptimized.formattedFileSize, color: .mfSuccess)
                ProjectionKPI(title: "Potential Savings", value: data.potentialSavings.formattedFileSize, color: .mfPrimary)
                ProjectionKPI(title: "Monthly Pace", value: data.currentPaceMonthly.formattedFileSize, color: .mfInfo)
            }

            // Confidence bands chart
            if !data.confidenceBands.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Projected Cumulative Savings")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.mfTextSecondary)

                    Chart {
                        ForEach(data.confidenceBands) { band in
                            AreaMark(
                                x: .value("Month", band.month),
                                yStart: .value("Low", band.low),
                                yEnd: .value("High", band.high)
                            )
                            .foregroundStyle(Color.mfPrimary.opacity(0.15))

                            LineMark(
                                x: .value("Month", band.month),
                                y: .value("Mid", band.mid)
                            )
                            .foregroundStyle(Color.mfPrimary)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                        }
                    }
                    .frame(height: 160)
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                                .foregroundStyle(Color.mfGlassBorder)
                            AxisValueLabel {
                                if let v = value.as(Int.self) {
                                    Text(v.formattedFileSize)
                                        .font(.system(size: 8))
                                        .foregroundColor(.mfTextMuted)
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 6)) { value in
                            AxisValueLabel {
                                Text(value.as(String.self) ?? "")
                                    .font(.system(size: 8))
                                    .foregroundColor(.mfTextMuted)
                                    .rotationEffect(.degrees(-45))
                            }
                        }
                    }

                    // Legend
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Rectangle().fill(Color.mfPrimary).frame(width: 12, height: 2)
                            Text("Expected").font(.system(size: 9)).foregroundColor(.mfTextMuted)
                        }
                        HStack(spacing: 4) {
                            Rectangle().fill(Color.mfPrimary.opacity(0.15)).frame(width: 12, height: 8)
                            Text("Confidence Range").font(.system(size: 9)).foregroundColor(.mfTextMuted)
                        }
                    }
                }
                .padding(16)
                .background(Color.mfSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}

struct ProjectionKPI: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.mfTextMuted)
            Text(value)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
