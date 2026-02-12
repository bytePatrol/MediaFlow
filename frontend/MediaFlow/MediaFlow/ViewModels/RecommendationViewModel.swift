import SwiftUI

@MainActor
class RecommendationViewModel: ObservableObject {
    @Published var recommendations: [Recommendation] = []
    @Published var summary: RecommendationSummary?
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
            recommendations = try await service.getRecommendations(type: selectedType)
            summary = try await service.getRecommendationSummary()
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
