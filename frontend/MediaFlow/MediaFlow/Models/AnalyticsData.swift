import Foundation

struct AnalyticsOverview: Codable {
    let totalMediaSize: Int
    let totalItems: Int
    let potentialSavings: Int
    let activeTranscodes: Int
    let completedTranscodes: Int
    let totalSavingsAchieved: Int
    let avgCompressionRatio: Double
    let totalTranscodeTime: Double
    var librariesSynced: Int = 0
    var workersOnline: Int = 0
    var lastAnalysisDate: String? = nil
}

struct StorageBreakdown: Codable {
    let labels: [String]
    let values: [Int]
    let percentages: [Double]
    let colors: [String]
}

struct CodecDistribution: Codable {
    let codecs: [String]
    let counts: [Int]
    let sizes: [Int]
}
