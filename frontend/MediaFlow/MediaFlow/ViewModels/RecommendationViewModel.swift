import SwiftUI

@MainActor
class RecommendationViewModel: ObservableObject {
    @Published var recommendations: [Recommendation] = []
    @Published var summary: RecommendationSummary?
    @Published var analysisHistory: [AnalysisRunInfo] = []
    @Published var savingsAchieved: SavingsAchievedInfo?
    @Published var librarySections: [LibrarySection] = []
    @Published var isLoading: Bool = false
    @Published var isGenerating: Bool = false
    @Published var selectedType: String? = nil
    @Published var selectedLibraryId: Int? = nil
    @Published var groupedRecommendations: [(String, [Recommendation])] = []

    private let service: BackendService

    init(service: BackendService = BackendService()) {
        self.service = service
    }

    private func rebuildGroupedRecommendations() {
        let categoryOrder = [
            "codec_upgrade", "quality_overkill", "duplicate", "low_quality",
            "storage_optimization", "audio_optimization", "container_modernize",
            "hdr_to_sdr", "batch_similar", "viewing_pattern",
        ]
        let grouped = Dictionary(grouping: recommendations, by: { $0.type })
        var result: [(String, [Recommendation])] = []
        for category in categoryOrder {
            if let recs = grouped[category], !recs.isEmpty {
                result.append((category, recs))
            }
        }
        for (category, recs) in grouped {
            if !categoryOrder.contains(category) && !recs.isEmpty {
                result.append((category, recs))
            }
        }
        groupedRecommendations = result
    }

    func loadRecommendations() async {
        isLoading = true
        do {
            async let recsReq = service.getRecommendations(type: selectedType, libraryId: selectedLibraryId)
            async let summaryReq = service.getRecommendationSummary(libraryId: selectedLibraryId)
            async let historyReq = service.getAnalysisHistory(limit: 10)
            async let savingsReq = service.getSavingsAchieved()
            async let sectionsReq = service.getLibrarySections()
            let (recs, sum, hist, sav, sections) = try await (recsReq, summaryReq, historyReq, savingsReq, sectionsReq)
            recommendations = recs
            summary = sum
            analysisHistory = hist
            savingsAchieved = sav
            librarySections = sections
            rebuildGroupedRecommendations()
        } catch {
            print("Failed to load recommendations: \(error)")
        }
        isLoading = false
    }

    func runAnalysis() async {
        isGenerating = true
        do {
            if let libraryId = selectedLibraryId {
                let _ = try await service.analyzeLibrary(libraryId: libraryId)
            } else {
                let _ = try await service.generateRecommendations()
            }
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

    func dismissRecommendation(_ id: Int, reason: String? = nil) async {
        do {
            if let reason = reason {
                try await service.dismissRecommendationWithReason(id: id, reason: reason)
            } else {
                try await service.dismissRecommendationWithReason(id: id, reason: nil)
            }
        } catch {
            print("Failed to dismiss: \(error)")
        }
        await loadRecommendations()
    }
}
