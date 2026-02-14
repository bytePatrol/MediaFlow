import SwiftUI
import Charts

struct AnalyticsDashboardView: View {
    @StateObject private var viewModel = AnalyticsViewModel()

    private let timeRanges = [7, 30, 90, 365]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 1. Header bar
                HStack {
                    Text("Analytics Dashboard")
                        .font(.mfTitle)

                    Spacer()

                    // Time range picker
                    HStack(spacing: 0) {
                        ForEach(timeRanges, id: \.self) { days in
                            Button {
                                Task { await viewModel.updateTimeRange(days) }
                            } label: {
                                Text(days == 365 ? "1y" : "\(days)d")
                                    .font(.system(size: 11, weight: viewModel.selectedTimeRange == days ? .bold : .medium))
                                    .foregroundColor(viewModel.selectedTimeRange == days ? .white : .mfTextSecondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(viewModel.selectedTimeRange == days ? Color.mfPrimary : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(3)
                    .background(Color.mfSurfaceLight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Button {
                        viewModel.exportPDF()
                    } label: {
                        HStack(spacing: 5) {
                            if viewModel.isExportingPDF {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.down.doc.fill")
                                    .font(.system(size: 11))
                            }
                            Text("Export PDF")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.mfTextSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(Color.mfSurfaceLight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isExportingPDF)

                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13))
                            .foregroundColor(.mfTextSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.mfSurfaceLight)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                // Error banner
                if let error = viewModel.errorMessage {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.mfWarning)
                        Text(error)
                            .font(.mfCaption)
                            .foregroundColor(.mfWarning)
                        Spacer()
                        Button("Retry") { Task { await viewModel.refresh() } }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.mfPrimary)
                            .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(Color.mfWarning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                // 2. Health Score hero card
                if let health = viewModel.healthScore {
                    healthScoreCard(health)
                }

                // 3. Trend KPI cards
                trendKPICards

                // 4. Predictions card
                if let pred = viewModel.predictions, pred.dailyRate > 0 {
                    predictionsCard(pred)
                }

                // 5. Charts row
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        savingsChart
                        codecChart
                    }
                    VStack(spacing: 16) {
                        savingsChart
                        codecChart
                    }
                }

                // 6. Resolution Distribution
                if let res = viewModel.resolutions, !res.resolutions.isEmpty {
                    resolutionChart(res)
                }

                // 7. Server Performance table
                if !viewModel.serverPerformance.isEmpty {
                    serverPerformanceTable
                }

                // 8. Top Savings Opportunities
                if !viewModel.topOpportunities.isEmpty {
                    topOpportunitiesSection
                }

                // 9. Cloud Costs card
                if let costSummary = viewModel.cloudCosts,
                   costSummary.currentMonthTotal > 0 || costSummary.activeInstanceRunningCost > 0 {
                    cloudCostsCard(costSummary)
                }
            }
            .padding(24)
        }
        .background(Color.mfBackground)
        .task { await viewModel.loadAll() }
    }

    // MARK: - Health Score Card

    private func healthScoreCard(_ health: HealthScoreResponse) -> some View {
        HStack(spacing: 24) {
            // Circular gauge
            ZStack {
                Circle()
                    .stroke(Color.mfSurfaceLight, lineWidth: 10)
                    .frame(width: 100, height: 100)
                Circle()
                    .trim(from: 0, to: CGFloat(health.score) / 100.0)
                    .stroke(gradeColor(health.grade), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(health.grade)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(gradeColor(health.grade))
                    Text("\(health.score)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.mfTextMuted)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Library Health Score")
                    .font(.mfSubheadline)
                healthMetricBar(label: "Modern Codecs", value: health.modernCodecPct)
                healthMetricBar(label: "Bitrate Quality", value: health.bitratePct)
                healthMetricBar(label: "Modern Containers", value: health.containerPct)
                healthMetricBar(label: "Audio Efficiency", value: health.audioPct)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .cardStyle()
        .hoverCard()
    }

    private func healthMetricBar(label: String, value: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.mfTextSecondary)
                .frame(width: 110, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.mfSurfaceLight)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(value >= 75 ? Color.mfSuccess : value >= 50 ? Color.mfWarning : Color.mfError)
                        .frame(width: geo.size.width * CGFloat(min(value, 100)) / 100)
                }
            }
            .frame(height: 6)
            Text("\(Int(value))%")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.mfTextMuted)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .mfSuccess
        case "B": return Color(red: 0.4, green: 0.8, blue: 0.3)
        case "C": return .mfWarning
        case "D": return Color(red: 0.9, green: 0.5, blue: 0.2)
        default: return .mfError
        }
    }

    // MARK: - Trend KPI Cards

    private var trendKPICards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 400))], spacing: 16) {
            trendCard(title: "Total Media Size", value: viewModel.overview?.totalMediaSize.formattedFileSize ?? "--", trend: trendFor("items_added"))
            trendCard(title: "Total Savings", value: viewModel.overview?.totalSavingsAchieved.formattedFileSize ?? "--", trend: trendFor("storage_saved"))
            trendCard(title: "Completed Jobs", value: "\(viewModel.overview?.completedTranscodes ?? 0)", trend: trendFor("jobs_completed"))
            trendCard(title: "Workers Online", value: "\(viewModel.overview?.workersOnline ?? 0)", trend: nil)
        }
    }

    private func trendFor(_ metric: String) -> TrendData? {
        viewModel.trends?.trends.first { $0.metric == metric }
    }

    private func trendCard(title: String, value: String, trend: TrendData?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.mfTextMuted)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)
            if let trend = trend {
                HStack(spacing: 4) {
                    Image(systemName: trend.direction == "up" ? "arrow.up.right" : trend.direction == "down" ? "arrow.down.right" : "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("\(String(format: "%.1f", abs(trend.changePct)))%")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(trend.direction == "up" ? .mfSuccess : trend.direction == "down" ? .mfError : .mfTextMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardStyle()
        .hoverCard()
    }

    // MARK: - Predictions Card

    private func predictionsCard(_ pred: PredictionResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.mfPrimary)
                Text("Savings Forecast")
                    .font(.mfSubheadline)
                Spacer()
                Text("Confidence: \(Int(pred.confidence * 100))%")
                    .font(.mfCaption)
                    .foregroundColor(.mfTextMuted)
            }
            Text("At your current pace...")
                .font(.mfBody)
                .foregroundColor(.mfTextSecondary)
            HStack(spacing: 24) {
                forecastItem(label: "30 days", value: Int(pred.predicted30d).formattedFileSize)
                forecastItem(label: "90 days", value: Int(pred.predicted90d).formattedFileSize)
                forecastItem(label: "1 year", value: Int(pred.predicted365d).formattedFileSize)
            }
        }
        .padding(20)
        .cardStyle()
    }

    private func forecastItem(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.mfSuccess)
            Text(label)
                .font(.mfCaption)
                .foregroundColor(.mfTextMuted)
        }
    }

    // MARK: - Charts

    private var savingsChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Savings Over Time")
                .font(.mfSubheadline)
            if !viewModel.savingsHistory.isEmpty {
                Chart(viewModel.savingsHistory) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Savings", point.cumulativeSavings)
                    )
                    .foregroundStyle(Color.mfPrimary.opacity(0.2).gradient)
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Savings", point.cumulativeSavings)
                    )
                    .foregroundStyle(Color.mfPrimary)
                }
                .frame(height: 220)
                .chartXAxis(.hidden)
            } else {
                Text("No data yet")
                    .font(.mfCaption)
                    .foregroundColor(.mfTextMuted)
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
                        SectorMark(
                            angle: .value("Count", pair.1),
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

    // MARK: - Resolution Distribution

    private func resolutionChart(_ res: ResolutionDistribution) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resolution Distribution")
                .font(.mfSubheadline)
            Chart {
                ForEach(Array(zip(res.resolutions, res.counts).enumerated()), id: \.offset) { _, pair in
                    BarMark(
                        x: .value("Resolution", pair.0),
                        y: .value("Count", pair.1)
                    )
                    .foregroundStyle(Color.mfPrimary.gradient)
                    .cornerRadius(4)
                }
            }
            .frame(height: 180)
        }
        .padding(20)
        .cardStyle()
    }

    // MARK: - Server Performance Table

    private var serverPerformanceTable: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Server Performance")
                .font(.mfSubheadline)

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Server").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Jobs").frame(width: 60, alignment: .trailing)
                    Text("Avg FPS").frame(width: 70, alignment: .trailing)
                    Text("Compression").frame(width: 90, alignment: .trailing)
                    Text("Time").frame(width: 70, alignment: .trailing)
                    Text("Fail Rate").frame(width: 70, alignment: .trailing)
                }
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.mfTextMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider().background(Color.mfGlassBorder)

                ForEach(viewModel.serverPerformance) { server in
                    HStack {
                        HStack(spacing: 6) {
                            Text(server.serverName)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            if server.isCloud {
                                Text("CLOUD")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.mfPrimary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.mfPrimary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(server.totalJobs)").frame(width: 60, alignment: .trailing)
                        Text(server.avgFps != nil ? String(format: "%.1f", server.avgFps!) : "--").frame(width: 70, alignment: .trailing)
                        Text(server.avgCompression != nil ? String(format: "%.1f%%", server.avgCompression! * 100) : "--").frame(width: 90, alignment: .trailing)
                        Text(String(format: "%.1fh", server.totalTimeHours)).frame(width: 70, alignment: .trailing)
                        Text(String(format: "%.1f%%", server.failureRate * 100))
                            .foregroundColor(server.failureRate > 0.1 ? .mfError : .mfTextSecondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(.mfTextSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                    Divider().background(Color.mfGlassBorder.opacity(0.5))
                }
            }
        }
        .padding(20)
        .cardStyle()
    }

    // MARK: - Top Savings Opportunities

    private var topOpportunitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Top Savings Opportunities")
                .font(.mfSubheadline)

            ForEach(viewModel.topOpportunities) { opp in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(opp.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(opp.currentCodec ?? "unknown")
                                .font(.system(size: 10))
                                .foregroundColor(.mfTextMuted)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8))
                                .foregroundColor(.mfTextMuted)
                            Text(opp.recommendedCodec)
                                .font(.system(size: 10))
                                .foregroundColor(.mfSuccess)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(opp.fileSize.formattedFileSize)
                            .font(.mfMono)
                            .foregroundColor(.mfTextSecondary)
                        Text("~\(opp.estimatedSavings.formattedFileSize) savings")
                            .font(.system(size: 10))
                            .foregroundColor(.mfSuccess)
                    }
                }
                .padding(10)
                .background(Color.mfSurfaceLight.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(20)
        .cardStyle()
    }

    // MARK: - Cloud Costs Card

    private func cloudCostsCard(_ costSummary: CloudCostSummary) -> some View {
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
}
