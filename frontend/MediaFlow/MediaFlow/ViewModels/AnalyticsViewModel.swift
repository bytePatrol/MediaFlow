import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
class AnalyticsViewModel: ObservableObject {
    @Published var overview: AnalyticsOverview?
    @Published var storage: StorageBreakdown?
    @Published var codecs: CodecDistribution?
    @Published var resolutions: ResolutionDistribution?
    @Published var savingsHistory: [SavingsHistoryPoint] = []
    @Published var trends: TrendsResponse?
    @Published var predictions: PredictionResponse?
    @Published var serverPerformance: [ServerPerformanceInfo] = []
    @Published var healthScore: HealthScoreResponse?
    @Published var topOpportunities: [SavingsOpportunity] = []
    @Published var cloudCosts: CloudCostSummary?
    @Published var isLoading: Bool = false
    @Published var isExportingPDF: Bool = false
    @Published var errorMessage: String?
    @Published var selectedTimeRange: Int = 30

    private let service: BackendService

    init(service: BackendService = BackendService()) {
        self.service = service
    }

    func loadAll() async {
        isLoading = true
        errorMessage = nil

        // Load core data in parallel
        async let overviewTask = service.getAnalyticsOverview()
        async let storageTask = service.getStorageBreakdown()
        async let codecTask = service.getCodecDistribution()
        async let resolutionTask = service.getResolutionDistribution()
        async let healthTask = service.getHealthScore()

        do {
            let (o, s, c, r, h) = try await (overviewTask, storageTask, codecTask, resolutionTask, healthTask)
            overview = o
            storage = s
            codecs = c
            resolutions = r
            healthScore = h
        } catch {
            errorMessage = "Failed to load analytics: \(error.localizedDescription)"
        }

        // Load time-dependent data in parallel
        async let trendsTask = service.getTrends(days: selectedTimeRange)
        async let predictionsTask = service.getPredictions()
        async let historyTask = service.getSavingsHistory(days: selectedTimeRange)
        async let perfTask = service.getServerPerformance()
        async let oppsTask = service.getTopOpportunities()

        do {
            let (t, p, hist, perf, opps) = try await (trendsTask, predictionsTask, historyTask, perfTask, oppsTask)
            trends = t
            predictions = p
            savingsHistory = hist
            serverPerformance = perf
            topOpportunities = opps
        } catch {
            // Non-critical — partial load is OK
        }

        // Cloud costs (optional, non-blocking)
        do { cloudCosts = try await service.getCloudCostSummary() } catch {}

        isLoading = false
    }

    func refresh() async {
        await loadAll()
    }

    func updateTimeRange(_ days: Int) async {
        selectedTimeRange = days
        // Reload time-dependent data
        do {
            async let trendsTask = service.getTrends(days: days)
            async let historyTask = service.getSavingsHistory(days: days)
            let (t, h) = try await (trendsTask, historyTask)
            trends = t
            savingsHistory = h
        } catch {}
    }

    func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "mediaflow-health-report.pdf"
        panel.title = "Export Health Report"
        panel.prompt = "Save"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isExportingPDF = true
        errorMessage = nil

        Task {
            do {
                let data = try await service.downloadHealthReport()
                try data.write(to: url)
            } catch {
                errorMessage = "Failed to export PDF: \(error.localizedDescription)"
            }
            isExportingPDF = false
        }
    }
}
