import Foundation

struct TagInfo: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let color: String
    var mediaCount: Int?
}

struct MediaItem: Identifiable, Codable, Hashable {
    let id: Int
    let plexLibraryId: Int
    let plexRatingKey: String
    let title: String
    var year: Int?
    var durationMs: Int?
    var thumbUrl: String?
    var filePath: String?
    var fileSize: Int?
    var container: String?
    var videoCodec: String?
    var videoProfile: String?
    var videoBitrate: Int?
    var width: Int?
    var height: Int?
    var resolutionTier: String?
    var frameRate: Double?
    var isHdr: Bool = false
    var hdrFormat: String?
    var bitDepth: Int?
    var audioCodec: String?
    var audioChannels: Int?
    var audioChannelLayout: String?
    var audioBitrate: Int?
    var playCount: Int = 0
    var genres: [String]?
    var directors: [String]?
    var libraryTitle: String?
    var tags: [TagInfo]?

    // Computed properties
    var resolutionBadgeText: String {
        guard let tier = resolutionTier else { return "Unknown" }
        if tier == "4K" && isHdr { return "4K HDR" }
        return tier
    }

    var codecDisplayName: String {
        guard let codec = videoCodec else { return "--" }
        let profile = videoProfile ?? ""
        switch codec.lowercased() {
        case "hevc", "h265": return "HEVC \(profile)"
        case "h264", "avc": return "AVC \(profile)"
        case "av1": return "AV1"
        case "vc1": return "VC-1"
        default: return codec.uppercased()
        }
    }

    var audioDisplayName: String {
        guard let codec = audioCodec else { return "--" }
        let channels = audioChannelLayout ?? (audioChannels.map { "\($0)ch" } ?? "")
        switch codec.lowercased() {
        case "truehd": return "TrueHD \(channels)"
        case "dts-hd", "dca": return "DTS-HD \(channels)"
        case "ac3", "eac3": return "AC3 \(channels)"
        case "aac": return "AAC \(channels)"
        case "flac": return "FLAC \(channels)"
        default: return "\(codec.uppercased()) \(channels)"
        }
    }

    var formattedFileSize: String {
        fileSize?.formattedFileSize ?? "--"
    }

    var formattedBitrate: String {
        guard let bitrate = videoBitrate else { return "--" }
        let mbps = Double(bitrate) / 1_000
        return String(format: "%.1f", mbps)
    }

    var formattedDuration: String {
        guard let ms = durationMs else { return "--" }
        let totalMinutes = ms / 60000
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 { return "\(hours)h \(String(format: "%02d", minutes))m" }
        return "\(minutes)m"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MediaItem, rhs: MediaItem) -> Bool {
        lhs.id == rhs.id
    }
}

struct FilteredItemIdsResponse: Codable {
    let ids: [Int]
    let total: Int
    let totalSize: Int
}

struct PaginatedMediaResponse: Codable {
    let items: [MediaItem]
    let total: Int
    let page: Int
    let pageSize: Int
    let totalPages: Int
}
