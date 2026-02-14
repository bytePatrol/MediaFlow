import SwiftUI

struct MediaTableView: View {
    @ObservedObject var viewModel: LibraryViewModel
    @State private var showColumnPicker = false

    var body: some View {
        VStack(spacing: 0) {
            // Table Header
            HStack(spacing: 0) {
                // Checkbox
                Button { viewModel.selectAll() } label: {
                    Image(systemName: viewModel.selectedItems.count == viewModel.items.count && !viewModel.items.isEmpty ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundColor(.mfPrimary)
                }
                .buttonStyle(.plain)
                .frame(width: 32)
                .help("Select all")

                SortableHeader(title: "Media Title", field: "title", currentSort: viewModel.sortBy, ascending: viewModel.sortAscending) {
                    viewModel.toggleSort("title")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(viewModel.columnConfig.visibleColumns) { column in
                    // Visible resize divider between columns
                    ColumnDividerHandle(column: column, columnConfig: viewModel.columnConfig)

                    SortableHeader(
                        title: column.displayTitle,
                        field: column.sortField,
                        currentSort: viewModel.sortBy,
                        ascending: viewModel.sortAscending
                    ) {
                        viewModel.toggleSort(column.sortField)
                    }
                    .frame(width: viewModel.columnConfig.width(for: column) - 12, alignment: .leading)
                }

                // Column picker button
                Button { showColumnPicker.toggle() } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                }
                .buttonStyle(.plain)
                .help("Choose columns")
                .popover(isPresented: $showColumnPicker, arrowEdge: .bottom) {
                    ColumnPickerView(columnConfig: viewModel.columnConfig)
                }
                .frame(width: 24)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.mfTextMuted)
            .textCase(.uppercase)
            .tracking(1)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.mfSurface.opacity(0.95))

            Divider().background(Color.mfGlassBorder)

            // Table Body
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.items) { item in
                        MediaRowView(
                            item: item,
                            isSelected: viewModel.selectedItems.contains(item.id),
                            columnConfig: viewModel.columnConfig,
                            onToggle: { viewModel.toggleSelection(item.id) }
                        )
                        Divider().background(Color.mfGlassBorder)
                    }

                    // Load more trigger
                    if viewModel.currentPage < viewModel.totalPages {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                Task { await viewModel.loadNextPage() }
                            }
                    }

                    if viewModel.isLoading {
                        ProgressView()
                            .padding()
                    }
                }
            }
        }
    }
}

// MARK: - Column Divider Handle

struct ColumnDividerHandle: View {
    let column: TableColumn
    @ObservedObject var columnConfig: ColumnConfig
    @State private var dragStartWidth: CGFloat = 0
    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        // Full hit-area background (white at near-zero opacity receives hit tests, Color.clear does not)
        Color.white.opacity(0.001)
            .frame(width: 12, height: 16)
            .overlay {
                // Visible bar
                RoundedRectangle(cornerRadius: 1)
                    .fill(isDragging ? Color.mfPrimary : (isHovering ? Color.mfTextMuted : Color.mfGlassBorder))
                    .frame(width: isDragging ? 2 : 1)
            }
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else if !isDragging {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            dragStartWidth = columnConfig.width(for: column)
                            isDragging = true
                        }
                        let newWidth = dragStartWidth - value.translation.width
                        columnConfig.setWidth(newWidth, for: column)
                    }
                    .onEnded { _ in
                        isDragging = false
                        NSCursor.pop()
                    }
            )
    }
}

// MARK: - Column Picker

struct ColumnPickerView: View {
    @ObservedObject var columnConfig: ColumnConfig

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Columns")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.mfTextMuted)
                .textCase(.uppercase)
                .tracking(1)
                .padding(.bottom, 2)

            ForEach(TableColumn.allCases) { column in
                Button {
                    columnConfig.toggle(column)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: columnConfig.isVisible(column) ? "checkmark.square.fill" : "square")
                            .foregroundColor(columnConfig.isVisible(column) ? .mfPrimary : .mfTextMuted)
                            .font(.system(size: 13))
                        Text(column.displayTitle)
                            .font(.system(size: 12))
                            .foregroundColor(.white)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 160)
    }
}

// MARK: - Sortable Header

struct SortableHeader: View {
    let title: String
    let field: String
    let currentSort: String
    let ascending: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                Text(title)
                if currentSort == field {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(currentSort == field ? .mfPrimary : .mfTextMuted)
    }
}

// MARK: - Grid View

struct MediaGridView: View {
    @ObservedObject var viewModel: LibraryViewModel

    let columns = [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(viewModel.items) { item in
                    MediaGridCard(item: item, isSelected: viewModel.selectedItems.contains(item.id)) {
                        viewModel.toggleSelection(item.id)
                    }
                    .onAppear {
                        if item.id == viewModel.items.last?.id,
                           viewModel.currentPage < viewModel.totalPages {
                            Task { await viewModel.loadNextPage() }
                        }
                    }
                }
            }
            .padding(16)

            if viewModel.isLoading {
                ProgressView()
                    .padding()
            }
        }
    }
}

struct MediaGridCard: View {
    let item: MediaItem
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack(alignment: .topTrailing) {
                AsyncImage(url: URL(string: "http://localhost:9876/api/library/thumb/\(item.id)")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(2/3, contentMode: .fill)
                            .clipped()
                    case .failure:
                        thumbnailPlaceholder
                    case .empty:
                        thumbnailPlaceholder
                            .overlay(ProgressView().scaleEffect(0.5))
                    @unknown default:
                        thumbnailPlaceholder
                    }
                }
                .aspectRatio(2/3, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.mfPrimary)
                        .padding(6)
                }
            }

            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)

            HStack {
                QualityBadge(resolution: item.resolutionTier ?? "Unknown", isHdr: item.isHdr)
                Spacer()
                Text(item.formattedFileSize)
                    .font(.mfMonoSmall)
                    .foregroundColor(.mfTextMuted)
            }
        }
        .padding(8)
        .background(isSelected ? Color.mfPrimary.opacity(0.1) : Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.mfPrimary.opacity(0.5) : Color.mfGlassBorder, lineWidth: 1)
        )
        .onTapGesture { onTap() }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.mfSurfaceLight)
            .aspectRatio(2/3, contentMode: .fit)
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 24))
                    .foregroundColor(.mfTextMuted)
            )
    }
}
