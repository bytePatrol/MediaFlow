import SwiftUI

struct RecommendationsView: View {
    @StateObject private var viewModel = RecommendationViewModel()

    let typeFilters = [
        ("All", nil as String?),
        ("Codec Upgrade", "codec_upgrade"),
        ("Quality Overkill", "quality_overkill"),
        ("Duplicates", "duplicate"),
        ("Low Quality", "low_quality"),
        ("Storage", "storage_optimization"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Intelligence")
                        .font(.mfTitle)
                    Text("AI-powered recommendations for your media library.")
                        .font(.mfBody)
                        .foregroundColor(.mfTextSecondary)
                }

                Spacer()

                if let summary = viewModel.summary {
                    VStack(alignment: .trailing) {
                        Text("Total Potential Savings")
                            .font(.mfCaption)
                            .foregroundColor(.mfTextMuted)
                        Text(summary.totalEstimatedSavings.formattedFileSize)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.mfSuccess)
                    }
                }

                Button {
                    Task { await viewModel.runAnalysis() }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isGenerating {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "brain")
                        }
                        Text(viewModel.isGenerating ? "Analyzing..." : "Run Analysis")
                    }
                    .primaryButton()
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGenerating)
            }
            .padding(24)

            // Type Filter Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(typeFilters, id: \.0) { label, type in
                        Button {
                            viewModel.selectedType = type
                            Task { await viewModel.loadRecommendations() }
                        } label: {
                            Text(label)
                                .font(.system(size: 12, weight: viewModel.selectedType == type ? .semibold : .medium))
                                .foregroundColor(viewModel.selectedType == type ? .mfPrimary : .mfTextSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(viewModel.selectedType == type ? Color.mfPrimary.opacity(0.1) : Color.mfSurface)
                                .clipShape(Capsule())
                                .overlay(Capsule().stroke(viewModel.selectedType == type ? Color.mfPrimary.opacity(0.3) : Color.mfGlassBorder))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 16)

            Divider().background(Color.mfGlassBorder)

            // Recommendations List
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.recommendations) { rec in
                        RecommendationCardView(recommendation: rec, onDismiss: {
                            Task { await viewModel.dismissRecommendation(rec.id) }
                        })
                    }

                    if viewModel.recommendations.isEmpty && !viewModel.isLoading {
                        VStack(spacing: 12) {
                            Image(systemName: "lightbulb")
                                .font(.system(size: 40))
                                .foregroundColor(.mfTextMuted)
                            Text("No recommendations yet")
                                .font(.mfBody)
                                .foregroundColor(.mfTextSecondary)
                            Text("Run analysis to generate recommendations.")
                                .font(.mfCaption)
                                .foregroundColor(.mfTextMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
                .padding(24)
            }
        }
        .background(Color.mfBackground)
        .task { await viewModel.loadRecommendations() }
    }
}
