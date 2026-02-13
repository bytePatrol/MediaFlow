import Foundation

enum NavigationItem: String, CaseIterable, Identifiable {
    case library = "Library"
    case quickTranscode = "Quick Transcode"
    case processing = "Processing"
    case servers = "Servers"
    case analytics = "Analytics"
    case intelligence = "Intelligence"
    case settings = "Settings"
    case logs = "Logs"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .library: return "books.vertical"
        case .quickTranscode: return "bolt.fill"
        case .processing: return "gearshape.2"
        case .servers: return "server.rack"
        case .analytics: return "chart.bar.xaxis"
        case .intelligence: return "brain"
        case .settings: return "gear"
        case .logs: return "doc.text.magnifyingglass"
        }
    }

    var label: String { rawValue }

    /// Whether this item is a sub-item visually indented under a parent
    var isSubItem: Bool {
        switch self {
        case .quickTranscode: return true
        default: return false
        }
    }
}
