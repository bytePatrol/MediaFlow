import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var appState: AppState
    @Binding var isPresented: Bool
    @State private var searchText = ""
    @State private var mediaResults: [MediaItem] = []
    @State private var isSearchingMedia = false
    @State private var cachedSections: [LibrarySection] = []
    @FocusState private var isSearchFocused: Bool

    private let searchDebouncer = Debouncer(duration: .milliseconds(300))
    private let backendService = BackendService()

    // MARK: - Commands

    var commands: [CommandItem] {
        var items: [CommandItem] = []

        // Navigation commands
        for nav in NavigationItem.allCases {
            items.append(CommandItem(
                name: "Go to \(nav.label)",
                icon: nav.icon,
                category: .navigation,
                action: {
                    appState.recordPaletteAction(label: "Go to \(nav.label)", icon: nav.icon)
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
                appState.recordPaletteAction(label: "Sync Libraries", icon: "arrow.triangle.2.circlepath")
                appState.selectedNavItem = .library
                isPresented = false
            }
        ))
        items.append(CommandItem(
            name: "Run Analysis",
            icon: "brain",
            category: .actions,
            action: {
                appState.recordPaletteAction(label: "Run Analysis", icon: "brain")
                appState.selectedNavItem = .intelligence
                isPresented = false
            }
        ))
        items.append(CommandItem(
            name: "Export Analytics PDF",
            icon: "doc.richtext",
            category: .actions,
            action: {
                appState.recordPaletteAction(label: "Export Analytics PDF", icon: "doc.richtext")
                appState.selectedNavItem = .analytics
                isPresented = false
            }
        ))
        items.append(CommandItem(
            name: "Open Settings",
            icon: "gear",
            category: .actions,
            action: {
                appState.recordPaletteAction(label: "Open Settings", icon: "gear")
                appState.selectedNavItem = .settings
                isPresented = false
            }
        ))
        items.append(CommandItem(
            name: "Quick Transcode",
            icon: "bolt.fill",
            category: .actions,
            action: {
                appState.recordPaletteAction(label: "Quick Transcode", icon: "bolt.fill")
                appState.selectedNavItem = .quickTranscode
                isPresented = false
            }
        ))

        // Dynamic library-scoped actions
        let query = searchText.lowercased()
        if query.contains("analy") || query.contains("recomm") {
            for section in cachedSections {
                items.append(CommandItem(
                    name: "Run Analysis for \(section.title)",
                    icon: "brain",
                    category: .actions,
                    subtitle: "\(section.totalItems) items - \(section.serverName)",
                    action: {
                        appState.recordPaletteAction(label: "Run Analysis for \(section.title)", icon: "brain")
                        Task {
                            _ = try? await backendService.analyzeLibrary(libraryId: section.id)
                        }
                        appState.selectedNavItem = .intelligence
                        isPresented = false
                    }
                ))
                items.append(CommandItem(
                    name: "Show Recommendations for \(section.title)",
                    icon: "lightbulb.fill",
                    category: .actions,
                    subtitle: "\(section.totalItems) items",
                    action: {
                        appState.recordPaletteAction(label: "Show Recommendations for \(section.title)", icon: "lightbulb.fill")
                        appState.selectedNavItem = .intelligence
                        isPresented = false
                    }
                ))
            }
        }

        return items
    }

    var filteredCommands: [CommandItem] {
        if searchText.isEmpty { return commands }
        let query = searchText.lowercased()
        return commands.filter { $0.name.lowercased().contains(query) }
    }

    // MARK: - Media Result Commands

    var mediaCommands: [CommandItem] {
        mediaResults.map { item in
            let subtitle = [
                item.year.map { "\($0)" },
                item.videoCodec?.uppercased(),
                item.formattedFileSize
            ].compactMap { $0 }.joined(separator: " - ")

            return CommandItem(
                name: item.title,
                icon: "film",
                category: .media,
                subtitle: subtitle,
                action: {
                    appState.recordPaletteAction(label: item.title, icon: "film")
                    appState.selectedMediaItems = [item.id]
                    appState.selectedNavItem = .library
                    isPresented = false
                }
            )
        }
    }

    // MARK: - Recent Commands

    var recentCommands: [CommandItem] {
        appState.recentPaletteActions.prefix(5).map { action in
            CommandItem(
                name: action.label,
                icon: action.icon,
                category: .recent,
                action: {
                    // Re-execute the action by matching against known commands
                    if let match = commands.first(where: { $0.name == action.label }) {
                        match.action()
                    } else {
                        // For media items, navigate to library
                        appState.selectedNavItem = .library
                        isPresented = false
                    }
                }
            )
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                TextField("Type a command or search media...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let first = filteredCommands.first {
                            first.action()
                        } else if let first = mediaCommands.first {
                            first.action()
                        }
                    }
                    .onChange(of: searchText) { _, newValue in
                        handleSearchChange(newValue)
                    }
                if isSearchingMedia {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                }
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        mediaResults = []
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
                    // Recent section (only when search is empty)
                    if searchText.isEmpty && !appState.recentPaletteActions.isEmpty {
                        sectionHeader("RECENT")

                        ForEach(recentCommands) { item in
                            commandRow(item)
                        }
                    }

                    // Navigation and Actions sections
                    ForEach([CommandItem.CommandCategory.navigation, .actions], id: \.self) { category in
                        let categoryItems = filteredCommands.filter { $0.category == category }
                        if !categoryItems.isEmpty {
                            sectionHeader(category.rawValue.uppercased())

                            ForEach(categoryItems) { item in
                                commandRow(item)
                            }
                        }
                    }

                    // Media results section
                    if !mediaCommands.isEmpty {
                        sectionHeader("MEDIA")

                        ForEach(mediaCommands) { item in
                            mediaRow(item)
                        }
                    }

                    // No results hint
                    if searchText.count >= 2 && filteredCommands.isEmpty && mediaResults.isEmpty && !isSearchingMedia {
                        HStack {
                            Spacer()
                            Text("No results found")
                                .font(.system(size: 12))
                                .foregroundColor(.mfTextMuted)
                                .padding(.vertical, 16)
                            Spacer()
                        }
                    }
                }
            }
            .frame(maxHeight: 360)
        }
        .frame(width: 460)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.mfGlassBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .onAppear {
            isSearchFocused = true
            loadSections()
        }
        .onExitCommand {
            isPresented = false
        }
    }

    // MARK: - Subviews

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.mfTextMuted)
            .tracking(1)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    private func commandRow(_ item: CommandItem) -> some View {
        Button {
            item.action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .frame(width: 20)
                    .foregroundColor(.mfPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 13))
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(.mfTextMuted)
                    }
                }
                Spacer()
                if item.category == .recent {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundColor(.mfTextMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func mediaRow(_ item: CommandItem) -> some View {
        Button {
            item.action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 13))
                    .frame(width: 20)
                    .foregroundColor(.mfPrimary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    if let subtitle = item.subtitle {
                        HStack(spacing: 6) {
                            ForEach(subtitle.components(separatedBy: " - "), id: \.self) { part in
                                Text(part)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.mfTextMuted)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.mfSurface.opacity(0.6))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }
                }
                Spacer()
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 11))
                    .foregroundColor(.mfTextMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Search Logic

    private func handleSearchChange(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            mediaResults = []
            isSearchingMedia = false
            return
        }

        isSearchingMedia = true
        let query = trimmed
        Task {
            await searchDebouncer.debounce { [backendService] in
                do {
                    let response = try await backendService.searchMediaItems(query: query, limit: 8)
                    await MainActor.run {
                        mediaResults = response.items
                        isSearchingMedia = false
                    }
                } catch {
                    await MainActor.run {
                        mediaResults = []
                        isSearchingMedia = false
                    }
                }
            }
        }
    }

    private func loadSections() {
        Task {
            if let sections = try? await backendService.getLibrarySections() {
                cachedSections = sections
            }
        }
    }
}
