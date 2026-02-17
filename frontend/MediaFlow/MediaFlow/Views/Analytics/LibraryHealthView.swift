import SwiftUI
import Charts

struct LibraryHealthView: View {
    let report: LibraryHealthReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with overall grade
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Library Health Report")
                        .font(.system(size: 16, weight: .bold))
                    Text("Per-library optimization analysis")
                        .font(.system(size: 12))
                        .foregroundColor(.mfTextSecondary)
                }
                Spacer()
                // Overall grade badge
                VStack(spacing: 2) {
                    Text(report.overallGrade)
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(gradeColor(report.overallGrade))
                    Text("Overall")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.mfTextMuted)
                }
                .frame(width: 60, height: 60)
                .background(gradeColor(report.overallGrade).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(gradeColor(report.overallGrade).opacity(0.3), lineWidth: 1))
            }
            .padding(16)
            .background(Color.mfSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Library cards grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(report.libraries) { card in
                    LibraryHealthCardView(card: card)
                }
            }
        }
    }

    private func gradeColor(_ grade: String) -> Color {
        switch grade {
        case "A": return .mfSuccess
        case "B": return .mfInfo
        case "C": return .mfWarning
        default: return .mfError
        }
    }
}

struct LibraryHealthCardView: View {
    let card: LibraryHealthCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Title + Grade
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.libraryTitle)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text("\(card.totalItems) items")
                        .font(.system(size: 11))
                        .foregroundColor(.mfTextSecondary)
                }
                Spacer()
                Text(card.healthGrade)
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(gradeColor)
                    .frame(width: 36, height: 36)
                    .background(gradeColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Optimization progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Modern Codecs")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.mfTextMuted)
                    Spacer()
                    Text(String(format: "%.0f%%", card.optimizationPct))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.mfSuccess)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.mfSurfaceLight)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.mfSuccess)
                            .frame(width: geo.size.width * min(1, card.optimizationPct / 100))
                    }
                }
                .frame(height: 6)
            }

            // Codec mini chart
            if !card.codecDistribution.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(card.codecDistribution.sorted(by: { $0.value > $1.value }).prefix(4)), id: \.key) { codec, count in
                        VStack(spacing: 2) {
                            Text(codec.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(.mfTextMuted)
                            Text("\(count)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.mfTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Color.mfSurfaceLight)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }

            // Size + Potential savings
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Size")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.mfTextMuted)
                    Text(card.totalSize.formattedFileSize)
                        .font(.system(size: 12, weight: .bold))
                }
                Spacer()
                if card.potentialSavings > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Can Save")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.mfTextMuted)
                        Text(card.potentialSavings.formattedFileSize)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.mfSuccess)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(gradeColor.opacity(0.15), lineWidth: 1)
        )
        .hoverCard()
    }

    private var gradeColor: Color {
        switch card.healthGrade {
        case "A": return .mfSuccess
        case "B": return .mfInfo
        case "C": return .mfWarning
        default: return .mfError
        }
    }
}
