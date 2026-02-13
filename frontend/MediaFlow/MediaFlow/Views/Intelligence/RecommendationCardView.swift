import SwiftUI

struct RecommendationCardView: View {
    let recommendation: Recommendation
    var onDismiss: (() -> Void)? = nil
    var onQueue: (() -> Void)? = nil

    var severityColor: Color {
        switch recommendation.severity {
        case "warning": return .mfWarning
        case "error", "critical": return .mfError
        default: return .mfInfo
        }
    }

    private var priorityColor: Color {
        guard let score = recommendation.priorityScore else { return .mfTextMuted }
        if score >= 70 { return .mfSuccess }
        if score >= 40 { return .mfWarning }
        return .orange
    }

    private var confidenceColor: Color {
        guard let c = recommendation.confidence else { return .mfTextMuted }
        if c >= 0.8 { return .mfSuccess }
        if c >= 0.4 { return .mfInfo }
        return .mfTextMuted
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            // Icon
            Image(systemName: recommendation.typeIcon)
                .font(.system(size: 18))
                .foregroundColor(severityColor)
                .frame(width: 40, height: 40)
                .background(severityColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(recommendation.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    Spacer()

                    // Priority score badge
                    if let score = recommendation.priorityScore {
                        Text("\(Int(score))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(priorityColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(priorityColor.opacity(0.12))
                            .clipShape(Capsule())
                            .help("Priority score: \(Int(score))/100")
                    }

                    if let savings = recommendation.estimatedSavings, savings > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 10))
                            Text(savings.formattedFileSize)
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.mfSuccess)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.mfSuccess.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }

                if let desc = recommendation.description {
                    Text(desc)
                        .font(.system(size: 12))
                        .foregroundColor(.mfTextSecondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    Text(recommendation.typeDisplayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.mfTextMuted)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.mfSurface)
                        .clipShape(Capsule())

                    // Confidence indicator
                    if recommendation.confidence != nil {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(confidenceColor)
                                .frame(width: 5, height: 5)
                            Text(recommendation.confidenceLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.mfTextMuted)
                        }
                        .help(recommendation.confidence ?? 0 >= 0.8
                              ? "Learned from previous transcodes"
                              : "Estimated from codec/bitrate analysis")
                    }

                    Spacer()

                    Button { onQueue?() } label: {
                        Text("Queue")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.mfPrimary)
                    }
                    .buttonStyle(.plain)

                    Button { onDismiss?() } label: {
                        Text("Dismiss")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.mfTextMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(severityColor.opacity(0.2), lineWidth: 1)
        )
    }
}
