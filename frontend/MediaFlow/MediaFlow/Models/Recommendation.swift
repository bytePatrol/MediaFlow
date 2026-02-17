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
    var estimatedTranscodeTime: Double?
    var estimatedCloudCost: Double?
    var roiScore: Double?
    var dismissReason: String?
    var roiLabel: String?
    var costLabel: String?

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

    var roiDisplayLabel: String {
        guard let roi = roiScore else { return "" }
        if roi >= 10 { return "Excellent ROI" }
        if roi >= 5 { return "Good ROI" }
        if roi >= 1 { return "Fair ROI" }
        return "Low ROI"
    }

    var roiColor: String {
        guard let roi = roiScore else { return "mfTextMuted" }
        if roi >= 10 { return "mfSuccess" }
        if roi >= 5 { return "mfInfo" }
        if roi >= 1 { return "mfWarning" }
        return "mfError"
    }

    var formattedTranscodeTime: String {
        guard let seconds = estimatedTranscodeTime, seconds > 0 else { return "--" }
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var formattedCloudCost: String {
        guard let cost = estimatedCloudCost, cost > 0 else { return "--" }
        return String(format: "$%.2f", cost)
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
