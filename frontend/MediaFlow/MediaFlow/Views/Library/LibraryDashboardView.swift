import SwiftUI

struct LibraryDashboardView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = LibraryViewModel()
    @State private var showFilterSidebar: Bool = false
    @State private var transcodePanel = TranscodeConfigPanel()

    var body: some View {
        VStack(spacing: 0) {
            // Filter Pill Bar
            if viewModel.filterState.isActive {
                FilterPillBarView(filterState: viewModel.filterState) {
                    Task { await viewModel.applyFilters() }
                }
            }

            // Action Bar
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

                    // View Mode Toggle
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
                    }
                    .padding(2)
                    .background(Color.mfSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.mfGlassBorder))

                    Button {
                        let selected = viewModel.items.filter { viewModel.selectedItems.contains($0.id) }
                        transcodePanel.show(mediaItems: selected)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "film")
                                .font(.system(size: 11))
                            Text("Transcode")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .primaryButton()
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.selectedItems.isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.mfBackground.opacity(0.6))

            // Main Content
            HStack(spacing: 0) {
                if showFilterSidebar {
                    FilterSidebarView(filterState: viewModel.filterState) {
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
        .task {
            await viewModel.loadSections()
            await viewModel.loadItems()
        }
    }
}
