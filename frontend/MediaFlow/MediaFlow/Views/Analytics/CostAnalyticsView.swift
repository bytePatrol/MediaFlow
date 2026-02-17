import SwiftUI
import Charts

struct CostAnalyticsView: View {
    let data: CostAnalyticsResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header KPIs
            HStack(spacing: 12) {
                CostKPICard(title: "Total Cloud Cost", value: String(format: "$%.2f", data.totalCloudCost), icon: "cloud", color: .mfPrimary)
                CostKPICard(title: "Cloud Jobs", value: "\(data.totalJobsCloud)", icon: "cpu", color: .mfInfo)
                CostKPICard(title: "Cost/GB Saved", value: String(format: "$%.4f", data.costPerGbSaved), icon: "arrow.down.circle", color: .mfSuccess)
                CostKPICard(title: "Monthly Projection", value: String(format: "$%.2f", data.monthlyProjection), icon: "calendar", color: .mfWarning)
            }

            // Cloud vs Local comparison
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cloud vs Local Cost")
                        .font(.system(size: 13, weight: .bold))

                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Cloud GPU")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.mfTextMuted)
                            Text(String(format: "$%.2f", data.cloudVsLocal["cloudCost"] ?? data.cloudVsLocal["cloud_cost"] ?? 0))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.mfPrimary)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Local (est.)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.mfTextMuted)
                            Text(String(format: "$%.2f", data.cloudVsLocal["localEstimatedCost"] ?? data.cloudVsLocal["local_estimated_cost"] ?? 0))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.mfTextSecondary)
                        }

                        Spacer()

                        let savings = data.cloudVsLocal["savings"] ?? 0
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(savings > 0 ? "Local Saved" : "Cloud Saved")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.mfTextMuted)
                            Text(String(format: "$%.2f", abs(savings)))
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.mfSuccess)
                        }
                    }
                }
                .padding(16)
                .background(Color.mfSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Monthly trend chart
            VStack(alignment: .leading, spacing: 8) {
                Text("Monthly Cloud Spend")
                    .font(.system(size: 13, weight: .bold))

                Chart {
                    ForEach(data.monthlyTrend) { item in
                        BarMark(
                            x: .value("Month", item.month),
                            y: .value("Cost", item.cost)
                        )
                        .foregroundStyle(Color.mfPrimary.gradient)
                        .cornerRadius(4)
                    }
                }
                .frame(height: 150)
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4]))
                            .foregroundStyle(Color.mfGlassBorder)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(String(format: "$%.0f", v))
                                    .font(.system(size: 9))
                                    .foregroundColor(.mfTextMuted)
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
}

struct CostKPICard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.mfTextMuted)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.mfTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
