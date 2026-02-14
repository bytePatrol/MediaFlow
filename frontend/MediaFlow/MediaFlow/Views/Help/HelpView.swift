import SwiftUI

struct HelpView: View {
    @State private var searchText = ""
    @State private var selectedTopic: HelpTopic?

    private var filteredTopics: [HelpTopic] {
        guard !searchText.isEmpty else { return HelpContent.allTopics }
        let query = searchText.lowercased()
        return HelpContent.allTopics.filter { topic in
            topic.title.lowercased().contains(query)
            || topic.summary.lowercased().contains(query)
            || topic.searchKeywords.contains(where: { $0.contains(query) })
        }
    }

    private var groupedTopics: [(HelpCategory, [HelpTopic])] {
        HelpCategory.allCases.compactMap { category in
            let topics = filteredTopics.filter { $0.category == category }
            return topics.isEmpty ? nil : (category, topics)
        }
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        Group {
            if let topic = selectedTopic {
                HelpTopicView(topic: topic) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTopic = nil
                    }
                }
            } else {
                topicGrid
            }
        }
        .background(Color.mfBackground)
    }

    private var topicGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Help")
                            .font(.mfTitle)
                            .foregroundColor(.mfTextPrimary)
                        Text("Learn how to use MediaFlow and troubleshoot issues")
                            .font(.mfBody)
                            .foregroundColor(.mfTextSecondary)
                    }
                    Spacer()
                }

                // Search
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.mfTextMuted)
                    TextField("Search help topics...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.mfBody)
                        .foregroundColor(.mfTextPrimary)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.mfTextMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.mfSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.mfGlassBorder, lineWidth: 1)
                )

                if groupedTopics.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 28))
                            .foregroundColor(.mfTextMuted)
                        Text("No topics match \"\(searchText)\"")
                            .font(.mfBody)
                            .foregroundColor(.mfTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }

                // Category sections
                ForEach(groupedTopics, id: \.0) { category, topics in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: category.icon)
                                .font(.system(size: 10, weight: .bold))
                            Text(category.rawValue)
                        }
                        .mfSectionHeader()

                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(topics) { topic in
                                HelpTopicCard(topic: topic) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedTopic = topic
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Topic Card

private struct HelpTopicCard: View {
    let topic: HelpTopic
    let action: () -> Void

    private var categoryColor: Color {
        switch topic.category {
        case .gettingStarted: return .mfPrimary
        case .features: return .mfSuccess
        case .advanced: return .mfWarning
        case .reference: return .mfInfo
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: topic.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(categoryColor)
                    .frame(width: 36, height: 36)
                    .background(categoryColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 9))

                VStack(alignment: .leading, spacing: 4) {
                    Text(topic.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mfTextPrimary)
                        .lineLimit(1)
                    Text(topic.summary)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.mfTextSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
            .hoverHighlight()
        }
        .buttonStyle(.plain)
    }
}
