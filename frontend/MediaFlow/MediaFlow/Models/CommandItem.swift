import Foundation

struct CommandItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let category: CommandCategory
    let subtitle: String?
    let action: () -> Void

    init(name: String, icon: String, category: CommandCategory, subtitle: String? = nil, action: @escaping () -> Void) {
        self.name = name
        self.icon = icon
        self.category = category
        self.subtitle = subtitle
        self.action = action
    }

    enum CommandCategory: String, CaseIterable {
        case recent = "Recent"
        case navigation = "Navigation"
        case actions = "Actions"
        case media = "Media"
    }
}

struct RecentPaletteAction: Identifiable, Codable {
    let id: UUID
    let label: String
    let icon: String
    let timestamp: Date

    init(label: String, icon: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.label = label
        self.icon = icon
        self.timestamp = timestamp
    }
}
