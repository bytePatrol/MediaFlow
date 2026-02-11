import SwiftUI

@MainActor
class AnalyticsViewModel: ObservableObject {
    @Published var overview: AnalyticsOverview?
    @Published var storage: StorageBreakdown?
    @Published var codecs: CodecDistribution?
    @Published var resolutions: ResolutionDistribution?
    @Published var cloudCosts: CloudCostSummary?
    @Published var isLoading: Bool = false

    private let service: BackendService

    init(service: BackendService = BackendService()) {
        self.service = service
    }

    func loadAll() async {
        isLoading = true
        async let overviewTask = service.getAnalyticsOverview()
        async let storageTask = service.getStorageBreakdown()
        async let codecTask = service.getCodecDistribution()

        do {
            overview = try await overviewTask
            storage = try await storageTask
            codecs = try await codecTask
        } catch {
            print("Failed to load analytics: \(error)")
        }
        // Load cloud costs separately (non-blocking)
        do {
            cloudCosts = try await service.getCloudCostSummary()
        } catch {
            // Cloud costs are optional — API may not have data yet
        }
        isLoading = false
    }
}
