import Foundation

struct Recommendation: Identifiable, Codable {
    let id: Int
    var mediaItemId: Int?
    let type: String
    let severity: String
    let title: String
    var description: String?
    var estimatedSavings: Int?
    var suggestedPresetId: Int?
    var isDismissed: Bool = false
    var isActioned: Bool = false
    var priorityScore: Double?
    var confidence: Double?
    var analysisRunId: Int?
    var createdAt: String?
    var mediaTitle: String?
    var mediaFileSize: Int?

    var typeDisplayName: String {
        switch type {
        case "codec_upgrade": return "Codec Upgrade"
        case "quality_overkill": return "Quality Overkill"
        case "duplicate": return "Duplicate"
        case "low_quality": return "Low Quality"
        case "storage_optimization": return "Storage Optimization"
        case "audio_optimization": return "Audio Optimization"
        case "container_modernize": return "Container Modernize"
        case "hdr_to_sdr": return "HDR to SDR"
        case "batch_similar": return "Batch Transcode"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var typeIcon: String {
        switch type {
        case "codec_upgrade": return "arrow.up.circle"
        case "quality_overkill": return "exclamationmark.triangle"
        case "duplicate": return "doc.on.doc"
        case "low_quality": return "arrow.down.circle"
        case "storage_optimization": return "externaldrive"
        case "audio_optimization": return "speaker.wave.3"
        case "container_modernize": return "shippingbox"
        case "hdr_to_sdr": return "sun.max"
        case "batch_similar": return "square.stack.3d.up"
        default: return "lightbulb"
        }
    }

    var severityColor: String {
        switch severity {
        case "warning": return "mfWarning"
        case "error", "critical": return "mfError"
        default: return "mfInfo"
        }
    }

    var confidenceLabel: String {
        guard let c = confidence else { return "Unknown" }
        if c >= 0.8 { return "High" }
        if c >= 0.4 { return "Medium" }
        return "Low"
    }
}

struct RecommendationSummary: Codable {
    let total: Int
    let byType: [String: Int]
    let totalEstimatedSavings: Int
    let dismissedCount: Int
    let actionedCount: Int
}

struct AnalysisRunInfo: Codable, Identifiable {
    let id: Int
    var startedAt: String?
    var completedAt: String?
    var totalItemsAnalyzed: Int = 0
    var recommendationsGenerated: Int = 0
    var totalEstimatedSavings: Int = 0
    var trigger: String = "manual"
    var libraryId: Int?
    var libraryTitle: String?
}

struct SavingsCodecEntry: Codable {
    let sourceCodec: String
    let targetCodec: String
    let jobs: Int
    var originalSize: Int = 0
    var finalSize: Int = 0
    var saved: Int = 0
}

struct SavingsAchievedInfo: Codable {
    var totalJobs: Int = 0
    var totalOriginalSize: Int = 0
    var totalFinalSize: Int = 0
    var totalSaved: Int = 0
    var byCodec: [SavingsCodecEntry] = []
}
