import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool

    var commands: [CommandItem] {
        var items: [CommandItem] = []

        // Navigation commands
        for nav in NavigationItem.allCases {
            items.append(CommandItem(
                name: "Go to \(nav.label)",
                icon: nav.icon,
                category: .navigation,
                action: {
                    appState.selectedNavItem = nav
                    isPresented = false
                }
            ))
        }

        // Action commands
        items.append(CommandItem(
            name: "Sync Libraries",
            icon: "arrow.triangle.2.circlepath",
            category: .actions,
            action: {
                appState.selectedNavItem = .library
                isPresented = false
            }
        ))
        items.append(CommandItem(
            name: "Run Analysis",
            icon: "brain",
            category: .actions,
            action: {
                appState.selectedNavItem = .intelligence
                isPresented = false
            }
        ))
        items.append(CommandItem(
            name: "Export Analytics PDF",
            icon: "doc.richtext",
            category: .actions,
            action: {
                appState.selectedNavItem = .analytics
                isPresented = false
            }
        ))
        items.append(CommandItem(
            name: "Open Settings",
            icon: "gear",
            category: .actions,
            action: {
                appState.selectedNavItem = .settings
                isPresented = false
            }
        ))
        items.append(CommandItem(
            name: "Quick Transcode",
            icon: "bolt.fill",
            category: .actions,
            action: {
                appState.selectedNavItem = .quickTranscode
                isPresented = false
            }
        ))

        return items
    }

    var filteredCommands: [CommandItem] {
        if searchText.isEmpty { return commands }
        let query = searchText.lowercased()
        return commands.filter { $0.name.lowercased().contains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                TextField("Type a command...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let first = filteredCommands.first {
                            first.action()
                        }
                    }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Text("ESC")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            .padding(12)

            Divider()

            // Results
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(CommandItem.CommandCategory.allCases, id: \.self) { category in
                        let categoryItems = filteredCommands.filter { $0.category == category }
                        if !categoryItems.isEmpty {
                            Text(category.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)
                                .tracking(1)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 4)

                            ForEach(categoryItems) { item in
                                Button {
                                    item.action()
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: item.icon)
                                            .font(.system(size: 13))
                                            .frame(width: 20)
                                            .foregroundColor(.mfPrimary)
                                        Text(item.name)
                                            .font(.system(size: 13))
                                        Spacer()
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
        }
        .frame(width: 420)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.mfGlassBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .onAppear {
            isSearchFocused = true
        }
        .onExitCommand {
            isPresented = false
        }
    }
}
