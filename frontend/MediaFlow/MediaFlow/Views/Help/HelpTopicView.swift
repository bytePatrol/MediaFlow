import SwiftUI

struct HelpTopicView: View {
    let topic: HelpTopic
    let onBack: () -> Void

    private var categoryColor: Color {
        switch topic.category {
        case .gettingStarted: return .mfPrimary
        case .features: return .mfSuccess
        case .advanced: return .mfWarning
        case .reference: return .mfInfo
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Back button
                Button(action: onBack) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("All Topics")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.mfPrimary)
                }
                .buttonStyle(.plain)

                // Header
                HStack(spacing: 16) {
                    Image(systemName: topic.icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(categoryColor)
                        .frame(width: 52, height: 52)
                        .background(categoryColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 6) {
                        Text(topic.title)
                            .font(.mfTitle)
                            .foregroundColor(.mfTextPrimary)

                        Text(topic.category.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(categoryColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(categoryColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                // Sections
                ForEach(Array(topic.sections.enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.title)
                            .font(.mfHeadline)
                            .foregroundColor(.mfTextPrimary)

                        sectionContent(section.content)
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func sectionContent(_ content: HelpSectionContent) -> some View {
        switch content {
        case .text(let text):
            Text(text)
                .font(.mfBody)
                .foregroundColor(.mfTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(3)

        case .steps(let steps):
            VStack(alignment: .leading, spacing: 16) {
                ForEach(steps) { step in
                    HelpStepView(step: step)
                }
            }

        case .tips(let tips):
            VStack(spacing: 8) {
                ForEach(tips) { tip in
                    HelpTipView(tip: tip)
                }
            }

        case .shortcuts(let shortcuts):
            VStack(spacing: 6) {
                ForEach(shortcuts) { shortcut in
                    HelpShortcutRow(shortcut: shortcut)
                }
            }
            .padding(14)
            .cardStyle()

        case .troubleshoot(let items):
            VStack(spacing: 8) {
                ForEach(items) { item in
                    HelpTroubleshootCard(item: item)
                }
            }

        case .features(let features):
            VStack(alignment: .leading, spacing: 14) {
                ForEach(features) { feature in
                    HelpFeatureRow(feature: feature)
                }
            }
        }
    }
}
