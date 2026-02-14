import SwiftUI

struct LibraryDashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = LibraryViewModel()
    @State private var showFilterSidebar: Bool = false
    @State private var transcodePanel = TranscodeConfigPanel()
    @State private var showTagPopover: Bool = false
    @State private var showManageTags: Bool = false
    @State private var newTagName: String = ""
    @State private var newTagColor: String = "#256af4"
    @State private var collectionPanel = CollectionBuilderPanel()
    @State private var filterPresets: [FilterPresetInfo] = []
    @State private var showSavePreset = false
    @State private var presetName: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Filter Pill Bar
            if viewModel.filterState.isActive {
                FilterPillBarView(filterState: viewModel.filterState) {
                    Task { await viewModel.applyFilters() }
                }
            }

            actionBar

            selectAllBanner

            // Main Content
            HStack(spacing: 0) {
                if showFilterSidebar {
                    FilterSidebarView(filterState: viewModel.filterState, availableTags: viewModel.availableTags) {
                        Task { await viewModel.applyFilters() }
                    }
                    .frame(width: 240)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    Divider().background(Color.mfGlassBorder)
                }

                // Table / Grid
                Group {
                    if viewModel.viewMode == .list {
                        MediaTableView(viewModel: viewModel)
                    } else {
                        MediaGridView(viewModel: viewModel)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color.mfBackground)
        .searchable(text: $viewModel.searchText, prompt: "Search library items...")
        .sheet(isPresented: $showManageTags) {
            ManageTagsSheet(viewModel: viewModel)
        }
        .alert("Save Filter Preset", isPresented: $showSavePreset) {
            TextField("Preset name", text: $presetName)
            Button("Save") {
                Task {
                    let filters: [String: AnyCodable] = [:]  // Simplified preset
                    try? await BackendService().createFilterPreset(name: presetName, filters: filters)
                    presetName = ""
                    await loadPresets()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task {
            await viewModel.loadSections()
            await viewModel.loadTags()
            await viewModel.loadItems()
            await loadPresets()
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            HStack(spacing: 8) {
                Menu {
                    Button {
                        viewModel.filterState.libraryId = nil
                        Task { await viewModel.loadItems() }
                    } label: {
                        HStack {
                            Text("All Media")
                            if viewModel.filterState.libraryId == nil {
                                Image(systemName: "checkmark")
                            }
                        }
                    }

                    Divider()

                    ForEach(viewModel.sections) { section in
                        Button {
                            viewModel.filterState.libraryId = section.id
                            Task { await viewModel.loadItems() }
                        } label: {
                            HStack {
                                Text("\(section.title)  (\(section.totalItems))")
                                if viewModel.filterState.libraryId == section.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.sections.first(where: { $0.id == viewModel.filterState.libraryId })?.title ?? "All Media")
                            .font(.mfHeadline)
                            .foregroundColor(.white)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.mfTextMuted)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Text("\(viewModel.totalCount) items found")
                    .font(.mfCaption)
                    .foregroundColor(.mfTextMuted)
            }

            Spacer()

            HStack(spacing: 8) {
                // Filter Toggle
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFilterSidebar.toggle()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 14))
                        .frame(width: 28, height: 28)
                        .background(showFilterSidebar ? Color.mfPrimary.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .foregroundColor(showFilterSidebar ? .mfPrimary : .mfTextMuted)
                .hoverHighlight()
                .help("Toggle filters")

                // Filter presets
                if !filterPresets.isEmpty {
                    Menu {
                        ForEach(filterPresets) { preset in
                            Button(preset.name) {
                                // Load preset filter (simplified - applies name filter for now)
                                Task { await viewModel.loadItems() }
                            }
                        }
                        Divider()
                        ForEach(filterPresets) { preset in
                            Button(role: .destructive) {
                                Task {
                                    try? await BackendService().deleteFilterPreset(id: preset.id)
                                    await loadPresets()
                                }
                            } label: {
                                Label("Delete \(preset.name)", systemImage: "trash")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.below.square.filled.and.square")
                                .font(.system(size: 12))
                            Text("Presets")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .secondaryButton()
                    }
                }

                if viewModel.filterState.isActive {
                    Button {
                        showSavePreset = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.system(size: 12))
                            Text("Save Filter")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .secondaryButton()
                    }
                    .buttonStyle(.plain)
                }

                viewModeToggle

                selectionBadge

                tagButton

                collectionButton

                transcodeButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.mfBackground.opacity(0.6))
    }

    // MARK: - View Mode Toggle

    private var viewModeToggle: some View {
        HStack(spacing: 0) {
            Button {
                viewModel.viewMode = .list
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .background(viewModel.viewMode == .list ? Color.mfSurfaceLight : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .foregroundColor(viewModel.viewMode == .list ? .white : .mfTextMuted)
            .help("List view")

            Button {
                viewModel.viewMode = .grid
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 12))
                    .frame(width: 28, height: 28)
                    .background(viewModel.viewMode == .grid ? Color.mfSurfaceLight : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .foregroundColor(viewModel.viewMode == .grid ? .white : .mfTextMuted)
            .help("Grid view")
        }
        .padding(2)
        .background(Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfGlassBorder))
    }

    // MARK: - Selection Badge

    @ViewBuilder
    private var selectionBadge: some View {
        if !viewModel.selectedItems.isEmpty {
            Text("\(viewModel.selectedItems.count) selected")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.mfPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.mfPrimary.opacity(0.12))
                .clipShape(Capsule())
        }
    }

    // MARK: - Tag Button

    private var tagButton: some View {
        Button {
            showTagPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "tag")
                    .font(.system(size: 11))
                Text("Tag")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.mfSurface)
            .foregroundColor(viewModel.selectedItems.isEmpty ? .mfTextMuted : .mfTextPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfGlassBorder))
            .hoverHighlight()
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedItems.isEmpty)
        .popover(isPresented: $showTagPopover) {
            tagPopoverContent
        }
    }

    private var tagPopoverContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Apply Tags")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider().background(Color.mfGlassBorder)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.availableTags) { tag in
                        let isApplied = isTagAppliedToSelection(tag: tag)
                        Button {
                            Task {
                                if isApplied {
                                    await viewModel.removeTagsFromSelected(tagIds: [tag.id])
                                } else {
                                    await viewModel.applyTagsToSelected(tagIds: [tag.id])
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: tag.color))
                                    .frame(width: 10, height: 10)
                                Text(tag.name)
                                    .font(.system(size: 12))
                                    .foregroundColor(.mfTextPrimary)
                                Spacer()
                                if isApplied {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.mfPrimary)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 200)

            Divider().background(Color.mfGlassBorder)

            // New Tag row
            HStack(spacing: 6) {
                TextField("New tag...", text: $newTagName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.mfSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                Button {
                    guard !newTagName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    Task {
                        do {
                            let _ = try await viewModel.createTag(name: newTagName.trimmingCharacters(in: .whitespaces), color: newTagColor)
                            newTagName = ""
                        } catch {
                            print("Failed to create tag: \(error)")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.mfPrimary)
                }
                .buttonStyle(.plain)
                .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().background(Color.mfGlassBorder)

            Button {
                showTagPopover = false
                showManageTags = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gear")
                        .font(.system(size: 10))
                    Text("Manage Tags")
                        .font(.system(size: 11))
                }
                .foregroundColor(.mfTextMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 220)
        .background(Color.mfBackground)
    }

    private func isTagAppliedToSelection(tag: TagInfo) -> Bool {
        let selectedItems = viewModel.items.filter { viewModel.selectedItems.contains($0.id) }
        guard !selectedItems.isEmpty else { return false }
        return selectedItems.allSatisfy { item in
            item.tags?.contains(where: { $0.id == tag.id }) ?? false
        }
    }

    // MARK: - Collection Button

    private var collectionButton: some View {
        Button {
            openCollectionPanel()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                Text("Collection")
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.mfSurface)
            .foregroundColor(viewModel.selectedItems.isEmpty ? .mfTextMuted : .mfTextPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfGlassBorder))
            .hoverHighlight()
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedItems.isEmpty)
    }

    private func openCollectionPanel() {
        collectionPanel.show(
            mediaItemIds: Array(viewModel.selectedItems),
            sections: viewModel.sections,
            selectedLibraryId: viewModel.filterState.libraryId
        ) {
            appState.showToast(
                "Collection updated",
                icon: "checkmark.circle.fill",
                style: .success,
                duration: 5
            )
            viewModel.clearSelection()
        }
    }

    // MARK: - Transcode Button

    private var transcodeButton: some View {
        Button {
            openTranscodePanel()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "film")
                    .font(.system(size: 11))
                Text("Transcode")
                    .font(.system(size: 12, weight: .medium))
            }
            .primaryButton()
            .hoverHighlight()
        }
        .buttonStyle(.plain)
        .disabled(viewModel.selectedItems.isEmpty)
    }

    private func openTranscodePanel() {
        let selectionCount = viewModel.selectedItems.count
        if viewModel.hasSelectionBeyondPage {
            transcodePanel.show(
                mediaItemIds: Array(viewModel.selectedItems),
                totalSize: viewModel.allFilteredTotalSize
            ) {
                appState.showToast(
                    "\(selectionCount) transcode jobs queued",
                    icon: "checkmark.circle.fill",
                    style: .success,
                    duration: 5
                )
                viewModel.clearSelection()
            }
        } else {
            let selected = viewModel.items.filter { viewModel.selectedItems.contains($0.id) }
            transcodePanel.show(mediaItems: selected) {
                appState.showToast(
                    "\(selected.count) transcode jobs queued",
                    icon: "checkmark.circle.fill",
                    style: .success,
                    duration: 5
                )
                viewModel.clearSelection()
            }
        }
    }

    // MARK: - Select All Filtered Banner

    @ViewBuilder
    private var selectAllBanner: some View {
        if showSelectAllBanner {
            HStack(spacing: 6) {
                Text("Selected \(viewModel.items.count) on this page.")
                    .font(.system(size: 12))
                    .foregroundColor(.mfTextSecondary)

                Button {
                    Task { await viewModel.selectAllFiltered() }
                } label: {
                    Text("Select all \(viewModel.totalCount) matching items")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.mfPrimary)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isSelectingAll)

                if viewModel.isSelectingAll {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.mfPrimary.opacity(0.06))
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfPrimary.opacity(0.15)), alignment: .bottom)
        }
    }

    private func loadPresets() async {
        do {
            filterPresets = try await BackendService().getFilterPresets()
        } catch {}
    }

    private var showSelectAllBanner: Bool {
        !viewModel.selectedItems.isEmpty
            && viewModel.selectedItems.count == viewModel.items.count
            && viewModel.totalCount > viewModel.items.count
            && !viewModel.hasSelectionBeyondPage
    }
}

// MARK: - Manage Tags Sheet

struct ManageTagsSheet: View {
    @ObservedObject var viewModel: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var newName: String = ""
    @State private var newColor: String = "#256af4"
    @State private var editingTag: TagInfo? = nil
    @State private var editName: String = ""

    private let colorPresets = ["#256af4", "#e53e3e", "#38a169", "#d69e2e", "#805ad5", "#dd6b20", "#319795", "#d53f8c"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Manage Tags")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.mfPrimary)
            }
            .padding(16)

            Divider().background(Color.mfGlassBorder)

            List {
                ForEach(viewModel.availableTags) { tag in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(Color(hex: tag.color))
                            .frame(width: 12, height: 12)

                        if editingTag?.id == tag.id {
                            TextField("Name", text: $editName, onCommit: {
                                Task {
                                    await viewModel.updateTag(id: tag.id, name: editName, color: nil)
                                    editingTag = nil
                                }
                            })
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                        } else {
                            Text(tag.name)
                                .font(.system(size: 13))
                                .foregroundColor(.mfTextPrimary)
                                .onTapGesture(count: 2) {
                                    editingTag = tag
                                    editName = tag.name
                                }
                        }

                        Spacer()

                        Text("\(tag.mediaCount ?? 0) items")
                            .font(.system(size: 11))
                            .foregroundColor(.mfTextMuted)

                        Button {
                            Task { await viewModel.deleteTag(id: tag.id) }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.mfTextMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }

                // New tag row
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        ForEach(colorPresets, id: \.self) { color in
                            Circle()
                                .fill(Color(hex: color))
                                .frame(width: 14, height: 14)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: newColor == color ? 2 : 0)
                                )
                                .onTapGesture { newColor = color }
                        }
                    }

                    TextField("New tag name...", text: $newName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))

                    Button {
                        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        Task {
                            let _ = try? await viewModel.createTag(
                                name: newName.trimmingCharacters(in: .whitespaces),
                                color: newColor
                            )
                            newName = ""
                        }
                    } label: {
                        Text("Add")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.mfPrimary)
                    }
                    .buttonStyle(.plain)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .frame(width: 420, height: 350)
        .background(Color.mfBackground)
    }
}
