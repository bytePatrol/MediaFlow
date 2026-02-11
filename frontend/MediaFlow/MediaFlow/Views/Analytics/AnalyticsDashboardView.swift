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
