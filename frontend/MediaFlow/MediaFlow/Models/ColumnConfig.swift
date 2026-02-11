import SwiftUI

enum TableColumn: String, CaseIterable, Identifiable {
    case fileSize
    case resolution
    case codec
    case bitrate
    case audio

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .fileSize: return "Size"
        case .resolution: return "Resolution"
        case .codec: return "Codec"
        case .bitrate: return "Bitrate"
        case .audio: return "Audio"
        }
    }

    var sortField: String {
        switch self {
        case .fileSize: return "file_size"
        case .resolution: return "resolution_tier"
        case .codec: return "video_codec"
        case .bitrate: return "video_bitrate"
        case .audio: return "audio_codec"
        }
    }

    var defaultWidth: CGFloat {
        switch self {
        case .fileSize: return 85
        case .resolution: return 80
        case .codec: return 100
        case .bitrate: return 85
        case .audio: return 80
        }
    }

    var minWidth: CGFloat { 40 }
    var maxWidth: CGFloat { 250 }
}

class ColumnConfig: ObservableObject {
    @Published var visibleColumns: [TableColumn] = TableColumn.allCases
    @Published var columnWidths: [TableColumn: CGFloat] = [:]

    func width(for column: TableColumn) -> CGFloat {
        columnWidths[column] ?? column.defaultWidth
    }

    func setWidth(_ width: CGFloat, for column: TableColumn) {
        columnWidths[column] = min(max(width, column.minWidth), column.maxWidth)
    }

    func isVisible(_ column: TableColumn) -> Bool {
        visibleColumns.contains(column)
    }

    func toggle(_ column: TableColumn) {
        if let index = visibleColumns.firstIndex(of: column) {
            visibleColumns.remove(at: index)
        } else {
            // Insert in canonical order
            let allCases = TableColumn.allCases
            let insertIndex = visibleColumns.firstIndex { existing in
                guard let existingPos = allCases.firstIndex(of: existing),
                      let newPos = allCases.firstIndex(of: column) else { return false }
                return existingPos > newPos
            } ?? visibleColumns.endIndex
            visibleColumns.insert(column, at: insertIndex)
        }
    }
}
