import SwiftUI
import AppKit

// MARK: - NSPanel-based presenter

class CollectionBuilderPanel {
    private var panel: NSPanel?

    @MainActor
    func show(
        mediaItemIds: [Int],
        sections: [LibrarySection],
        selectedLibraryId: Int?,
        onComplete: @escaping () -> Void
    ) {
        guard panel == nil else { return }

        let content = CollectionBuilderPanelContent(
            dismiss: { [weak self] in self?.close() },
            mediaItemIds: mediaItemIds,
            sections: sections,
            selectedLibraryId: selectedLibraryId,
            onComplete: onComplete
        )

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 480, height: 520)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.becomesKeyOnlyIfNeeded = false
        panel.center()
        panel.isReleasedWhenClosed = false
        self.panel = panel

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.close()
        panel = nil
    }
}

// MARK: - Panel content

struct CollectionBuilderPanelContent: View {
    var dismiss: () -> Void
    let mediaItemIds: [Int]
    let sections: [LibrarySection]
    let selectedLibraryId: Int?
    var onComplete: () -> Void

    enum Mode: String, CaseIterable {
        case create = "Create New"
        case addToExisting = "Add to Existing"
    }

    @State private var mode: Mode = .create
    @State private var collectionName: String = ""
    @State private var existingCollections: [CollectionInfo] = []
    @State private var selectedCollectionId: String? = nil
    @State private var isLoading: Bool = true
    @State private var isSaving: Bool = false
    @State private var errorMessage: String = ""

    private let service = BackendService()

    private var currentSection: LibrarySection? {
        if let id = selectedLibraryId {
            return sections.first(where: { $0.id == id })
        }
        return sections.first
    }

    private var serverId: Int? {
        currentSection?.serverId
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                            .foregroundColor(.mfPrimary)
                        Text("Plex Collection")
                            .font(.mfHeadline)
                    }
                    Text("\(mediaItemIds.count) items selected")
                        .font(.mfCaption)
                        .foregroundColor(.mfTextSecondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.mfTextSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .bottom)

            if isLoading {
                Spacer()
                ProgressView("Loading collections...")
                    .foregroundColor(.mfTextSecondary)
                Spacer()
            } else {
                // Mode picker
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if mode == .create {
                            createModeContent
                        } else {
                            existingModeContent
                        }

                        if !errorMessage.isEmpty {
                            Text(errorMessage)
                                .font(.mfCaption)
                                .foregroundColor(.mfError)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.mfError.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .padding(20)
                }
            }

            // Footer
            HStack {
                Button { dismiss() } label: {
                    Text("Cancel").secondaryButton()
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    Task { await performAction() }
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: mode == .create ? "plus" : "plus.square.on.square")
                        }
                        Text(mode == .create ? "Create Collection" : "Add to Collection")
                    }
                    .primaryButton()
                }
                .buttonStyle(.plain)
                .disabled(isSaving || !canSubmit)
            }
            .padding(20)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .top)
        }
        .frame(width: 480, height: 520)
        .background(Color.mfBackground)
        .preferredColorScheme(.dark)
        .task { await loadCollections() }
    }

    // MARK: - Create Mode

    private var createModeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("COLLECTION NAME")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.mfTextMuted)
                    .tracking(0.5)
                TextField("My Collection", text: $collectionName)
                    .textFieldStyle(.roundedBorder)
            }

            if let section = currentSection {
                HStack(spacing: 8) {
                    Image(systemName: "building.2")
                        .font(.system(size: 11))
                        .foregroundColor(.mfTextMuted)
                    Text("Library: \(section.title)")
                        .font(.system(size: 12))
                        .foregroundColor(.mfTextSecondary)
                }
            }
        }
    }

    // MARK: - Existing Mode

    private var existingModeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if existingCollections.isEmpty {
                Text("No existing collections found in this library.")
                    .font(.mfBody)
                    .foregroundColor(.mfTextMuted)
                    .padding(.vertical, 20)
            } else {
                Text("SELECT A COLLECTION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.mfTextMuted)
                    .tracking(0.5)

                ForEach(existingCollections) { collection in
                    Button {
                        selectedCollectionId = collection.id
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 14))
                                .foregroundColor(selectedCollectionId == collection.id ? .mfPrimary : .mfTextMuted)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(collection.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.mfTextPrimary)
                                Text("\(collection.itemCount) items \u{2022} \(collection.sectionTitle)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.mfTextMuted)
                            }

                            Spacer()

                            if selectedCollectionId == collection.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.mfPrimary)
                                    .font(.system(size: 16))
                            }
                        }
                        .padding(10)
                        .background(
                            selectedCollectionId == collection.id
                                ? Color.mfPrimary.opacity(0.08)
                                : Color.mfSurface.opacity(0.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(
                                    selectedCollectionId == collection.id
                                        ? Color.mfPrimary.opacity(0.3)
                                        : Color.mfGlassBorder,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Actions

    private var canSubmit: Bool {
        if mode == .create {
            return !collectionName.trimmingCharacters(in: .whitespaces).isEmpty && serverId != nil
        } else {
            return selectedCollectionId != nil && serverId != nil
        }
    }

    private func loadCollections() async {
        isLoading = true
        guard let sid = serverId else {
            isLoading = false
            return
        }
        do {
            existingCollections = try await service.getCollections(serverId: sid)
        } catch {
            errorMessage = "Failed to load collections: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func performAction() async {
        guard let sid = serverId, let section = currentSection else { return }
        isSaving = true
        errorMessage = ""

        do {
            if mode == .create {
                _ = try await service.createCollection(
                    request: CollectionCreateRequest(
                        serverId: sid,
                        libraryId: section.id,
                        title: collectionName.trimmingCharacters(in: .whitespaces),
                        mediaItemIds: mediaItemIds
                    )
                )
            } else if let collectionId = selectedCollectionId {
                _ = try await service.addToCollection(
                    collectionId: collectionId,
                    request: CollectionAddRequest(
                        serverId: sid,
                        mediaItemIds: mediaItemIds
                    )
                )
            }
            onComplete()
            dismiss()
        } catch {
            errorMessage = "Failed: \(error.localizedDescription)"
        }
        isSaving = false
    }
}
