import SwiftUI

@MainActor
class RecommendationViewModel: ObservableObject {
    @Published var recommendations: [Recommendation] = []
    @Published var summary: RecommendationSummary?
    @Published var analysisHistory: [AnalysisRunInfo] = []
    @Published var savingsAchieved: SavingsAchievedInfo?
    @Published var isLoading: Bool = false
    @Published var isGenerating: Bool = false
    @Published var selectedType: String? = nil

    private let service: BackendService

    init(service: BackendService = BackendService()) {
        self.service = service
    }

    func loadRecommendations() async {
        isLoading = true
        do {
            async let recsReq = service.getRecommendations(type: selectedType)
            async let summaryReq = service.getRecommendationSummary()
            async let historyReq = service.getAnalysisHistory(limit: 10)
            async let savingsReq = service.getSavingsAchieved()
            let (recs, sum, hist, sav) = try await (recsReq, summaryReq, historyReq, savingsReq)
            recommendations = recs
            summary = sum
            analysisHistory = hist
            savingsAchieved = sav
        } catch {
            print("Failed to load recommendations: \(error)")
        }
        isLoading = false
    }

    func runAnalysis() async {
        isGenerating = true
        do {
            let _ = try await service.generateRecommendations()
            await loadRecommendations()
        } catch {
            print("Failed to generate: \(error)")
        }
        isGenerating = false
    }

    func queueRecommendation(_ id: Int) async {
        do {
            let _ = try await service.batchQueueRecommendations(ids: [id])
            await loadRecommendations()
        } catch {
            print("Failed to queue recommendation: \(error)")
        }
    }

    func dismissRecommendation(_ id: Int) async {
        let client = APIClient(baseURL: service.client.baseURL)
        struct Empty: Codable {}
        let _: [String: AnyCodable]? = try? await client.post("/api/recommendations/\(id)/dismiss")
        await loadRecommendations()
    }
}
