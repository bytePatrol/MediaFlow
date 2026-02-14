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
                        Text(viewModel.isGenerating
                             ? "Analyzing..."
                             : (viewModel.selectedLibraryId != nil ? "Analyze Library" : "Run Analysis"))
                    }
                    .primaryButton()
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGenerating)
            }
            .padding(24)

            // Library filter + Savings achieved banner
            HStack(spacing: 12) {
                // Library filter picker
                HStack(spacing: 6) {
                    Image(systemName: "building.columns")
                        .font(.system(size: 11))
                        .foregroundColor(.mfTextMuted)
                    Picker("Library", selection: $viewModel.selectedLibraryId) {
                        Text("All Libraries").tag(nil as Int?)
                        ForEach(viewModel.librarySections) { section in
                            Text(section.title).tag(section.id as Int?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200)
                    .onChange(of: viewModel.selectedLibraryId) { _, _ in
                        Task { await viewModel.loadRecommendations() }
                    }
                }

                if let savings = viewModel.savingsAchieved, savings.totalJobs > 0 {
                    Spacer()

                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.mfSuccess)

                    Text("\(savings.totalSaved.formattedFileSize) saved from \(savings.totalJobs) job\(savings.totalJobs == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.mfTextSecondary)

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
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color.mfSuccess.opacity(0.03))

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

                            if let libTitle = run.libraryTitle {
                                HStack(spacing: 3) {
                                    Image(systemName: "building.columns")
                                        .font(.system(size: 8))
                                    Text(libTitle)
                                        .font(.system(size: 9, weight: .medium))
                                }
                                .foregroundColor(.mfPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.mfPrimary.opacity(0.1))
                                .clipShape(Capsule())
                            }

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

            // Recommendations List — grouped by category
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if viewModel.selectedType != nil {
                        // When a specific type is selected, show flat list (already filtered)
                        ForEach(viewModel.recommendations) { rec in
                            RecommendationCardView(recommendation: rec, onDismiss: {
                                Task { await viewModel.dismissRecommendation(rec.id) }
                            }, onQueue: {
                                Task { await viewModel.queueRecommendation(rec.id) }
                            })
                        }
                    } else {
                        // Group by category with section headers
                        ForEach(viewModel.groupedRecommendations, id: \.0) { category, recs in
                            VStack(alignment: .leading, spacing: 8) {
                                // Section header
                                HStack(spacing: 8) {
                                    Image(systemName: categoryIcon(category))
                                        .font(.system(size: 12))
                                        .foregroundColor(.mfPrimary)
                                    Text(categoryDisplayName(category))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.mfTextPrimary)
                                    Text("\(recs.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.mfTextMuted)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.mfSurface)
                                        .clipShape(Capsule())
                                    Spacer()
                                }
                                .padding(.top, 8)

                                ForEach(recs) { rec in
                                    RecommendationCardView(recommendation: rec, onDismiss: {
                                        Task { await viewModel.dismissRecommendation(rec.id) }
                                    }, onQueue: {
                                        Task { await viewModel.queueRecommendation(rec.id) }
                                    })
                                }
                            }
                        }
                    }

                    if viewModel.recommendations.isEmpty && !viewModel.isLoading {
                        if let libId = viewModel.selectedLibraryId,
                           let section = viewModel.librarySections.first(where: { $0.id == libId }) {
                            EmptyStateView(
                                icon: "lightbulb",
                                title: "No recommendations for \(section.title)",
                                description: "Run analysis to generate optimization recommendations for this library.",
                                actionTitle: "Analyze Library",
                                action: { Task { await viewModel.runAnalysis() } }
                            )
                        } else {
                            EmptyStateView(
                                icon: "lightbulb",
                                title: "No recommendations yet",
                                description: "Run analysis to generate optimization recommendations for your library.",
                                actionTitle: "Run Analysis",
                                action: { Task { await viewModel.runAnalysis() } }
                            )
                        }
                    }
                }
                .padding(24)
            }
        }
        .background(Color.mfBackground)
        .task { await viewModel.loadRecommendations() }
    }

    private func categoryDisplayName(_ type: String) -> String {
        switch type {
        case "codec_upgrade": return "Codec Upgrade"
        case "quality_overkill": return "Quality Overkill"
        case "duplicate": return "Duplicates"
        case "low_quality": return "Low Quality"
        case "storage_optimization": return "Storage Optimization"
        case "audio_optimization": return "Audio Optimization"
        case "container_modernize": return "Container Modernize"
        case "hdr_to_sdr": return "HDR to SDR"
        case "batch_similar": return "Batch Transcode"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func categoryIcon(_ type: String) -> String {
        switch type {
        case "codec_upgrade": return "arrow.up.circle"
        case "quality_overkill": return "exclamationmark.triangle"
        case "duplicate": return "doc.on.doc"
        case "low_quality": return "arrow.down.circle"
        case "storage_optimization": return "externaldrive"
        case "audio_optimization": return "speaker.wave.3"
        case "container_modernize": return "shippingbox"
        case "hdr_to_sdr": return "sun.max"
        case "batch_similar": return "square.stack.3d.up"
        default: return "lightbulb"
        }
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
