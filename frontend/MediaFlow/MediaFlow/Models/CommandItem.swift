import Foundation

struct CommandItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let category: CommandCategory
    let action: () -> Void

    enum CommandCategory: String, CaseIterable {
        case navigation = "Navigation"
        case actions = "Actions"
    }
}
