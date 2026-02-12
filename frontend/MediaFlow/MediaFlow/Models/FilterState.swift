import Foundation

class FilterState: ObservableObject {
    @Published var resolutions: Set<String> = []
    @Published var videoCodecs: Set<String> = []
    @Published var audioCodecs: Set<String> = []
    @Published var hdrOnly: Bool = false
    @Published var minBitrate: Double? = nil
    @Published var maxBitrate: Double? = nil
    @Published var minSize: Int? = nil
    @Published var maxSize: Int? = nil
    @Published var libraryId: Int? = nil
    @Published var selectedTagIds: Set<Int> = []

    var isActive: Bool {
        !resolutions.isEmpty || !videoCodecs.isEmpty || !audioCodecs.isEmpty
        || hdrOnly || minBitrate != nil || maxBitrate != nil
        || minSize != nil || maxSize != nil || libraryId != nil
        || !selectedTagIds.isEmpty
    }

    var activeFilterCount: Int {
        var count = 0
        if !resolutions.isEmpty { count += 1 }
        if !videoCodecs.isEmpty { count += 1 }
        if !audioCodecs.isEmpty { count += 1 }
        if hdrOnly { count += 1 }
        if minBitrate != nil || maxBitrate != nil { count += 1 }
        if minSize != nil || maxSize != nil { count += 1 }
        if libraryId != nil { count += 1 }
        if !selectedTagIds.isEmpty { count += 1 }
        return count
    }

    var activePills: [FilterPill] {
        var pills: [FilterPill] = []
        if !resolutions.isEmpty {
            pills.append(FilterPill(category: "Resolution", value: resolutions.sorted().joined(separator: ", "), clearAction: { self.resolutions.removeAll() }))
        }
        if !videoCodecs.isEmpty {
            pills.append(FilterPill(category: "Codec", value: videoCodecs.sorted().joined(separator: ", "), clearAction: { self.videoCodecs.removeAll() }))
        }
        if !audioCodecs.isEmpty {
            pills.append(FilterPill(category: "Audio", value: audioCodecs.sorted().joined(separator: ", "), clearAction: { self.audioCodecs.removeAll() }))
        }
        if hdrOnly {
            pills.append(FilterPill(category: "HDR", value: "Only", clearAction: { self.hdrOnly = false }))
        }
        if !selectedTagIds.isEmpty {
            pills.append(FilterPill(category: "Tags", value: "\(selectedTagIds.count) selected", clearAction: { self.selectedTagIds.removeAll() }))
        }
        return pills
    }

    func clear() {
        resolutions.removeAll()
        videoCodecs.removeAll()
        audioCodecs.removeAll()
        hdrOnly = false
        minBitrate = nil
        maxBitrate = nil
        minSize = nil
        maxSize = nil
        libraryId = nil
        selectedTagIds.removeAll()
    }

    func toQueryItems() -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if !resolutions.isEmpty {
            items.append(URLQueryItem(name: "resolution", value: resolutions.joined(separator: ",")))
        }
        if !videoCodecs.isEmpty {
            items.append(URLQueryItem(name: "video_codec", value: videoCodecs.joined(separator: ",")))
        }
        if !audioCodecs.isEmpty {
            items.append(URLQueryItem(name: "audio_codec", value: audioCodecs.joined(separator: ",")))
        }
        if hdrOnly {
            items.append(URLQueryItem(name: "hdr_only", value: "true"))
        }
        if let min = minBitrate {
            items.append(URLQueryItem(name: "min_bitrate", value: "\(Int(min * 1000))"))
        }
        if let max = maxBitrate {
            items.append(URLQueryItem(name: "max_bitrate", value: "\(Int(max * 1000))"))
        }
        if let id = libraryId {
            items.append(URLQueryItem(name: "library_id", value: "\(id)"))
        }
        if !selectedTagIds.isEmpty {
            items.append(URLQueryItem(name: "tags", value: selectedTagIds.map { "\($0)" }.joined(separator: ",")))
        }
        return items
    }
}

struct FilterPill: Identifiable {
    let id = UUID()
    let category: String
    let value: String
    let clearAction: () -> Void
}
