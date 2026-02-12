import SwiftUI
import Combine

@MainActor
class LibraryViewModel: ObservableObject {
    @Published var items: [MediaItem] = []
    @Published var totalCount: Int = 0
    @Published var currentPage: Int = 1
    @Published var totalPages: Int = 1
    @Published var isLoading: Bool = false
    @Published var viewMode: ViewMode = .list
    @Published var selectedItems: Set<Int> = []
    @Published var searchText: String = ""
    @Published var sortBy: String = "title"
    @Published var sortAscending: Bool = true
    @Published var sections: [LibrarySection] = []
    @Published var filterState = FilterState()
    @Published var columnConfig = ColumnConfig()
    @Published var allFilteredTotalSize: Int = 0
    @Published var isSelectingAll: Bool = false

    private let service: BackendService
    private let debouncer = Debouncer(duration: .milliseconds(300))
    private var searchCancellable: AnyCancellable?
    private var columnConfigCancellable: AnyCancellable?

    enum ViewMode: String {
        case list, grid
    }

    init(service: BackendService = BackendService()) {
        self.service = service
        searchCancellable = $searchText
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { await self?.loadItems() }
            }
        // Forward columnConfig changes so header re-renders on resize
        columnConfigCancellable = columnConfig.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    func loadItems(page: Int = 1) async {
        isLoading = true
        currentPage = page

        do {
            var queryItems = filterState.toQueryItems()
            if !searchText.isEmpty {
                queryItems.append(URLQueryItem(name: "search", value: searchText))
            }
            queryItems.append(URLQueryItem(name: "sort_by", value: sortBy))
            queryItems.append(URLQueryItem(name: "sort_order", value: sortAscending ? "asc" : "desc"))

            let response = try await service.getLibraryItems(
                page: page,
                pageSize: 50,
                queryItems: queryItems
            )

            if page == 1 {
                items = response.items
            } else {
                items.append(contentsOf: response.items)
            }
            totalCount = response.total
            totalPages = response.totalPages
        } catch {
            print("Failed to load items: \(error)")
        }

        isLoading = false
    }

    func loadNextPage() async {
        guard currentPage < totalPages, !isLoading else { return }
        await loadItems(page: currentPage + 1)
    }

    func loadSections() async {
        do {
            sections = try await service.getLibrarySections()
        } catch {
            print("Failed to load sections: \(error)")
        }
    }

    func applyFilters() async {
        currentPage = 1
        await loadItems()
    }

    func clearFilters() async {
        filterState.clear()
        await loadItems()
    }

    func toggleSort(_ column: String) {
        if sortBy == column {
            sortAscending.toggle()
        } else {
            sortBy = column
            sortAscending = true
        }
        Task { await loadItems() }
    }

    func selectAll() {
        if selectedItems.count == items.count {
            selectedItems.removeAll()
        } else {
            selectedItems = Set(items.map(\.id))
        }
    }

    func toggleSelection(_ id: Int) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }

    func selectAllFiltered() async {
        isSelectingAll = true
        do {
            var queryItems = filterState.toQueryItems()
            if !searchText.isEmpty {
                queryItems.append(URLQueryItem(name: "search", value: searchText))
            }
            let response = try await service.getFilteredItemIds(queryItems: queryItems)
            selectedItems = Set(response.ids)
            allFilteredTotalSize = response.totalSize
        } catch {
            print("Failed to select all filtered: \(error)")
        }
        isSelectingAll = false
    }

    func clearSelection() {
        selectedItems.removeAll()
        allFilteredTotalSize = 0
    }

    var hasSelectionBeyondPage: Bool {
        let pageIds = Set(items.map(\.id))
        return selectedItems.contains(where: { !pageIds.contains($0) })
    }
}
