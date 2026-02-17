import SwiftUI

struct CodecStrategyView: View {
    let data: CodecStrategyResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Codec Strategy Advisor")
                        .font(.system(size: 16, weight: .bold))
                    Text("AI-recommended codec targets per library")
                        .font(.system(size: 12))
                        .foregroundColor(.mfTextSecondary)
                }
                Spacer()
                Image(systemName: "brain")
                    .font(.system(size: 20))
                    .foregroundColor(.mfPrimary)
            }

            // Per-library advice cards
            ForEach(data.advice) { advice in
                HStack(spacing: 14) {
                    // Codec transition arrow
                    VStack(spacing: 4) {
                        Text(advice.currentDominantCodec.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.mfWarning)
                        Image(systemName: "arrow.down")
                            .font(.system(size: 10))
                            .foregroundColor(.mfTextMuted)
                        Text(advice.recommendedTarget.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.mfSuccess)
                    }
                    .frame(width: 60)
                    .padding(.vertical, 8)
                    .background(Color.mfSurfaceLight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    // Info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(advice.libraryTitle)
                            .font(.system(size: 13, weight: .semibold))

                        Text(advice.rationale)
                            .font(.system(size: 11))
                            .foregroundColor(.mfTextSecondary)
                            .lineLimit(2)

                        HStack(spacing: 12) {
                            if advice.avgSavingsPct > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "chart.line.downtrend.xyaxis")
                                        .font(.system(size: 9))
                                    Text(String(format: "%.0f%% savings", advice.avgSavingsPct))
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.mfSuccess)
                            }

                            if advice.totalProjectedSavings > 0 {
                                HStack(spacing: 4) {
                                    Image(systemName: "externaldrive")
                                        .font(.system(size: 9))
                                    Text("Projected: \(advice.totalProjectedSavings.formattedFileSize)")
                                        .font(.system(size: 10, weight: .medium))
                                }
                                .foregroundColor(.mfInfo)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(12)
                .background(Color.mfSurface)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .hoverCard()
            }

            // Resolution recommendations
            if !data.resolutionRecommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Per-Resolution Recommendations")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mfTextSecondary)

                    HStack(spacing: 8) {
                        ForEach(data.resolutionRecommendations) { rec in
                            VStack(spacing: 6) {
                                Text(rec.resolution)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.mfTextPrimary)
                                Text(rec.bestCodec.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.mfSuccess)
                                if rec.avgSavings > 0 {
                                    Text(String(format: "%.0f%%", rec.avgSavings))
                                        .font(.system(size: 9))
                                        .foregroundColor(.mfTextMuted)
                                }
                                Text("\(rec.sampleSize) jobs")
                                    .font(.system(size: 8))
                                    .foregroundColor(.mfTextMuted)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .background(Color.mfSurfaceLight)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(16)
                .background(Color.mfSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
