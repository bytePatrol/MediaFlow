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
}

struct RecommendationSummary: Codable {
    let total: Int
    let byType: [String: Int]
    let totalEstimatedSavings: Int
    let dismissedCount: Int
    let actionedCount: Int
}
