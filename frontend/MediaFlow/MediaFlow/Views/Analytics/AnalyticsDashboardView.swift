import SwiftUI
import Charts

struct AnalyticsDashboardView: View {
    @StateObject private var viewModel = AnalyticsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                Text("Analytics Dashboard")
                    .font(.mfTitle)

                // KPI Cards
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 400))], spacing: 16) {
                    StatisticsCardView(
                        icon: "externaldrive",
                        iconColor: .mfPrimary,
                        title: "Total Media Size",
                        value: viewModel.overview?.totalMediaSize.formattedFileSize ?? "--",
                        trend: "+2.4 TB",
                        trendUp: true
                    )
                    StatisticsCardView(
                        icon: "wand.and.stars",
                        iconColor: .mfSuccess,
                        title: "Potential Savings",
                        value: viewModel.overview?.potentialSavings.formattedFileSize ?? "--",
                        subtitle: "OPTIMIZABLE"
                    )
                    StatisticsCardView(
                        icon: "speedometer",
                        iconColor: .mfWarning,
                        title: "Active Transcodes",
                        value: "\(viewModel.overview?.activeTranscodes ?? 0)",
                        subtitle: "STREAMS"
                    )
                    StatisticsCardView(
                        icon: "checkmark.circle",
                        iconColor: .mfSuccess,
                        title: "Total Savings",
                        value: viewModel.overview?.totalSavingsAchieved.formattedFileSize ?? "--",
                        subtitle: "ACHIEVED"
                    )
                }

                // Cloud Costs Card
                if let costSummary = viewModel.cloudCosts, costSummary.currentMonthTotal > 0 || costSummary.activeInstanceRunningCost > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "cloud.bolt.fill")
                                .foregroundColor(.mfPrimary)
                            Text("Cloud GPU Costs")
                                .font(.mfSubheadline)
                            Spacer()
                            Text("This Month")
                                .font(.mfCaption)
                                .foregroundColor(.mfTextMuted)
                        }
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TOTAL SPEND")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.mfTextMuted)
                                    .tracking(0.5)
                                Text("$\(String(format: "%.2f", costSummary.currentMonthTotal))")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.mfPrimary)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("ACTIVE RUNNING")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.mfTextMuted)
                                    .tracking(0.5)
                                Text("$\(String(format: "%.2f", costSummary.activeInstanceRunningCost))")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundColor(.mfWarning)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("CAP")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.mfTextMuted)
                                    .tracking(0.5)
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.mfSurfaceLight)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(costSummary.currentMonthTotal / costSummary.monthlyCap > 0.8 ? Color.mfError : Color.mfPrimary)
                                            .frame(width: geo.size.width * min(1, CGFloat(costSummary.currentMonthTotal / max(costSummary.monthlyCap, 1))))
                                    }
                                }
                                .frame(width: 120, height: 8)
                                Text("$\(String(format: "%.2f", costSummary.currentMonthTotal)) / $\(String(format: "%.0f", costSummary.monthlyCap))")
                                    .font(.system(size: 10))
                                    .foregroundColor(.mfTextSecondary)
                            }
                        }
                    }
                    .padding(20)
                    .cardStyle()
                }

                // Charts Row
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        storageChart
                        codecChart
                    }
                    VStack(spacing: 16) {
                        storageChart
                        codecChart
                    }
                }
            }
            .padding(24)
        }
        .background(Color.mfBackground)
        .task { await viewModel.loadAll() }
    }

    private var storageChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage by Codec")
                .font(.mfSubheadline)

            if let storage = viewModel.storage {
                Chart {
                    ForEach(Array(zip(storage.labels, storage.values).enumerated()), id: \.offset) { _, pair in
                        SectorMark(
                            angle: .value("Size", pair.1),
                            innerRadius: .ratio(0.6)
                        )
                        .foregroundStyle(by: .value("Codec", pair.0))
                    }
                }
                .chartLegend(position: .bottom)
                .frame(height: 220)
            } else {
                ProgressView()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .cardStyle()
    }

    private var codecChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Codec Distribution")
                .font(.mfSubheadline)

            if let codecs = viewModel.codecs {
                Chart {
                    ForEach(Array(zip(codecs.codecs, codecs.counts).enumerated()), id: \.offset) { _, pair in
                        BarMark(
                            x: .value("Codec", pair.0),
                            y: .value("Count", pair.1)
                        )
                        .foregroundStyle(Color.mfPrimary.gradient)
                        .cornerRadius(4)
                    }
                }
                .frame(height: 220)
            } else {
                ProgressView()
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .cardStyle()
    }
}
