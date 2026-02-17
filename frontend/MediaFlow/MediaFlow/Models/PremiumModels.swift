import Foundation

// MARK: - Automation Rules

struct AutomationRule: Identifiable, Codable {
    let id: Int
    var name: String
    var isEnabled: Bool
    var triggerType: String
    var conditionsJson: [AnyCodable]?
    var actionsJson: [AnyCodable]?
    var lastTriggeredAt: String?
    var triggerCount: Int = 0
    var createdAt: String?

    var triggerDisplayName: String {
        switch triggerType {
        case "analysis_complete": return "Analysis Completes"
        case "job_complete": return "Job Completes"
        case "job_failed": return "Job Fails"
        case "library_sync": return "Library Syncs"
        case "storage_threshold": return "Storage Threshold"
        case "schedule": return "Schedule"
        default: return triggerType.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct AutomationRuleCreateRequest: Codable {
    let name: String
    let triggerType: String
    var conditionsJson: [AnyCodable]?
    var actionsJson: [AnyCodable]?
    var isEnabled: Bool = true
}

// MARK: - Library Health

struct LibraryHealthCard: Identifiable, Codable {
    var id: Int { libraryId }
    let libraryId: Int
    let libraryTitle: String
    let totalItems: Int
    let totalSize: Int
    let codecDistribution: [String: Int]
    let resolutionDistribution: [String: Int]
    let optimizationPct: Double
    let healthScore: Int
    let healthGrade: String
    let potentialSavings: Int
    let avgBitrate: Double
    let hdrCount: Int

    var gradeColor: String {
        switch healthGrade {
        case "A": return "mfSuccess"
        case "B": return "mfInfo"
        case "C": return "mfWarning"
        default: return "mfError"
        }
    }
}

struct LibraryHealthReport: Codable {
    let libraries: [LibraryHealthCard]
    let overallScore: Int
    let overallGrade: String
    let totalPotentialSavings: Int
}

// MARK: - Codec Migration

struct CodecMigrationEntry: Codable, Identifiable {
    var id: String { date }
    let date: String
    let codecDistribution: [String: Int]
    let totalItems: Int
    let modernCodecPct: Double
}

struct CodecMigrationResponse: Codable {
    let current: [String: Int]
    let currentPct: [String: Float]
    let history: [CodecMigrationEntry]
    let totalItems: Int
    let modernPct: Double
    var libraryId: Int?
}

// MARK: - Cost Analytics

struct MonthlyCostEntry: Codable, Identifiable {
    var id: String { month }
    let month: String
    var cost: Double = 0
    var jobs: Int = 0
}

struct CostAnalyticsResponse: Codable {
    let totalCloudCost: Double
    let totalJobsCloud: Int
    let costPerGbSaved: Double
    let cloudVsLocal: [String: Double]
    let monthlyTrend: [MonthlyCostEntry]
    let monthlyProjection: Double
}

// MARK: - Worker Heatmap

struct WorkerHeatmapEntry: Codable, Identifiable {
    var id: String { "\(workerId)-\(hour)" }
    let workerId: Int
    let workerName: String
    let hour: Int
    let avgFps: Double
    let jobCount: Int
    let utilization: Double
}

struct WorkerInfo: Codable, Identifiable {
    let id: Int
    let name: String
}

struct WorkerHeatmapResponse: Codable {
    let entries: [WorkerHeatmapEntry]
    let workers: [WorkerInfo]
}

// MARK: - Job Timeline

struct JobTimelineEntry: Codable, Identifiable {
    var id: Int { jobId }
    let jobId: Int
    let title: String
    var workerId: Int?
    var workerName: String?
    let status: String
    var startedAt: String?
    var completedAt: String?
    var durationSeconds: Double?
    var sourceCodec: String?
    var targetCodec: String?
}

struct JobTimelineResponse: Codable {
    let jobs: [JobTimelineEntry]
    let workers: [WorkerInfo]
}

// MARK: - Codec Strategy

struct CodecStrategyAdvice: Codable, Identifiable {
    var id: Int { libraryId }
    let libraryId: Int
    let libraryTitle: String
    let currentDominantCodec: String
    let recommendedTarget: String
    let avgSavingsPct: Double
    let totalProjectedSavings: Int
    let rationale: String
}

struct ResolutionRecommendation: Codable, Identifiable {
    var id: String { resolution }
    let resolution: String
    let bestCodec: String
    var avgSavings: Double = 0
    var sampleSize: Int = 0
}

struct CodecStrategyResponse: Codable {
    let advice: [CodecStrategyAdvice]
    let resolutionRecommendations: [ResolutionRecommendation]
}

// MARK: - One-Click Optimize

struct OptimizeLibraryRequest: Codable {
    let libraryId: Int
    var presetId: Int?
    var minConfidence: Double = 0.5
    var maxItems: Int?
    var dryRun: Bool = false
}

struct OptimizeLibraryStatus: Codable {
    let sessionId: String
    let libraryId: Int
    var stage: String
    var progressPct: Double
    var itemsQueued: Int = 0
    var itemsCompleted: Int = 0
    var itemsTotal: Int = 0
    var estimatedSavings: Int = 0
    var actualSavings: Int = 0
    var message: String = ""

    var stageDisplayName: String {
        switch stage {
        case "syncing": return "Syncing Library"
        case "analyzing": return "Running Analysis"
        case "queuing": return "Queuing Jobs"
        case "transcoding": return "Transcoding"
        case "completed": return "Complete"
        case "failed": return "Failed"
        case "cancelled": return "Cancelled"
        default: return stage.capitalized
        }
    }

    var isActive: Bool {
        ["syncing", "analyzing", "queuing", "transcoding"].contains(stage)
    }
}

// MARK: - VMAF Quality

struct VMAFStatsResponse: Codable {
    var totalScored: Int = 0
    var avgScore: Double?
    var minScore: Double?
    var maxScore: Double?
    var byCodec: [VMAFCodecEntry] = []
}

struct VMAFCodecEntry: Codable, Identifiable {
    var id: String { "\(sourceCodec)-\(targetCodec)" }
    let sourceCodec: String
    let targetCodec: String
    let jobs: Int
    var avgVmaf: Double?
}

// MARK: - Storage Projection

struct ConfidenceBandEntry: Codable, Identifiable {
    var id: String { month }
    let month: String
    var low: Int = 0
    var mid: Int = 0
    var high: Int = 0
}

struct StorageSavingsProjection: Codable {
    let currentTotalSize: Int
    let ifAllOptimized: Int
    let potentialSavings: Int
    let currentPaceMonthly: Int
    var monthsToStorageLimit: Double?
    let confidenceBands: [ConfidenceBandEntry]
}

// MARK: - A/B Comparison

struct ComparisonThumbnail: Codable, Identifiable {
    var id: String { timestamp }
    let timestamp: String
    let original: String  // base64
    let transcoded: String  // base64
}

struct ComparisonThumbnailsResponse: Codable {
    let thumbnails: [ComparisonThumbnail]
}

struct ComparisonMetadata: Codable {
    let jobId: Int
    let sourceCodec: String?
    let sourceResolution: String?
    let sourceSize: Int?
    let sourceBitrate: Int?
    let targetCodec: String?
    let targetResolution: String?
    let targetSize: Int?
    let targetBitrate: Int?
    let vmafScore: Double?
    let sizeReduction: Double?
}

// MARK: - Queue Strategy

struct QueueStrategyResponse: Codable {
    let strategy: String
    let options: [String]
}

// MARK: - Dismiss with Reason

struct DismissWithReasonRequest: Codable {
    var reason: String?
}
