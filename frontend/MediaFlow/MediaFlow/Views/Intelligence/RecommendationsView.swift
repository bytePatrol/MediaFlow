import SwiftUI

struct RecommendationsView: View {
    @StateObject private var viewModel = RecommendationViewModel()
    @State private var showHistory: Bool = false

    let typeFilters: [(String, String?)] = [
        ("All", nil),
        ("Codec Upgrade", "codec_upgrade"),
        ("Quality Overkill", "quality_overkill"),
        ("Duplicates", "duplicate"),
        ("Low Quality", "low_quality"),
        ("Storage", "storage_optimization"),
        ("Audio", "audio_optimization"),
        ("Container", "container_modernize"),
        ("HDR", "hdr_to_sdr"),
        ("Batch", "batch_similar"),
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

            // Savings achieved banner
            if let savings = viewModel.savingsAchieved, savings.totalJobs > 0 {
                HStack(spacing: 16) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.mfSuccess)

                    Text("\(savings.totalSaved.formattedFileSize) saved from \(savings.totalJobs) completed job\(savings.totalJobs == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.mfTextSecondary)

                    Spacer()

                    // Last run indicator
                    if let lastRun = viewModel.analysisHistory.first {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(lastRun.trigger == "auto" ? Color.mfInfo : Color.mfPrimary)
                                .frame(width: 6, height: 6)
                            Text(lastRun.trigger == "auto" ? "Auto-analyzed" : "Manual analysis")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.mfTextMuted)
                        }
                    }

                    Button {
                        withAnimation { showHistory.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Text("History")
                                .font(.system(size: 11, weight: .medium))
                            Image(systemName: showHistory ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9))
                        }
                        .foregroundColor(.mfTextMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.mfSuccess.opacity(0.06))
            }

            // Analysis history (expandable)
            if showHistory && !viewModel.analysisHistory.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.analysisHistory) { run in
                        HStack(spacing: 12) {
                            Image(systemName: run.trigger == "auto" ? "arrow.clockwise" : "hand.tap")
                                .font(.system(size: 10))
                                .foregroundColor(run.trigger == "auto" ? .mfInfo : .mfPrimary)
                                .frame(width: 20)

                            if let started = run.startedAt {
                                Text(formatTimestamp(started))
                                    .font(.system(size: 11))
                                    .foregroundColor(.mfTextSecondary)
                                    .frame(width: 140, alignment: .leading)
                            }

                            Text("\(run.recommendationsGenerated) recs")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.mfTextSecondary)

                            Text(run.totalEstimatedSavings.formattedFileSize)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.mfSuccess)

                            Text(run.trigger.capitalized)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.mfTextMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.mfSurface)
                                .clipShape(Capsule())

                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(Color.mfSurface.opacity(0.3))
            }

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
                        }, onQueue: {
                            Task { await viewModel.queueRecommendation(rec.id) }
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

    private func formatTimestamp(_ iso: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: iso) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return iso
    }
}
