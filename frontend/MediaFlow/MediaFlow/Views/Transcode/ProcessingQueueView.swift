import SwiftUI

struct ProcessingQueueView: View {
    @StateObject private var viewModel = TranscodeViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 20))
                        .foregroundColor(.mfPrimary)
                    Text("Active Processing Queue")
                        .font(.mfHeadline)
                }

                Divider()
                    .frame(height: 30)

                // KPIs
                HStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ACTIVE JOBS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.mfTextMuted)
                            .tracking(1)
                        Text("\(String(format: "%02d", viewModel.queueStats?.totalActive ?? 0))")
                            .font(.mfMonoLarge)
                            .foregroundColor(.mfPrimary)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("AGGREGATE FPS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.mfTextMuted)
                            .tracking(1)
                        Text(String(format: "%.1f", viewModel.queueStats?.aggregateFps ?? 0))
                            .font(.mfMonoLarge)
                            .foregroundColor(.mfSuccess)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("QUEUE STATUS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.mfTextMuted)
                            .tracking(1)
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.mfSuccess)
                                .frame(width: 6, height: 6)
                            Text("Processing")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        Task { await viewModel.clearFinished() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                            Text("Clear All")
                        }
                        .secondaryButton()
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { let _ = await viewModel.clearCache() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "internaldrive")
                                .font(.system(size: 11))
                            Text("Clear Cache")
                        }
                        .secondaryButton()
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await viewModel.pauseAll() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.circle")
                                .font(.system(size: 11))
                            Text("Pause All")
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.mfError)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.mfError.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .background(Color.mfSurface)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .bottom)

            // Main content
            HSplitView {
                // Sidebar Filters
                VStack(alignment: .leading, spacing: 8) {
                    Text("FILTERS")
                        .mfSectionHeader()
                        .padding(.horizontal, 12)
                        .padding(.top, 12)

                    ForEach(TranscodeViewModel.JobFilter.allCases, id: \.self) { filter in
                        Button {
                            viewModel.selectedFilter = filter
                            Task { await viewModel.loadJobs() }
                        } label: {
                            HStack {
                                Image(systemName: filter.icon)
                                    .font(.system(size: 16))
                                Text(filter.rawValue)
                                    .font(.system(size: 13, weight: viewModel.selectedFilter == filter ? .semibold : .regular))
                                Spacer()
                            }
                            .foregroundColor(viewModel.selectedFilter == filter ? .mfPrimary : .mfTextSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(viewModel.selectedFilter == filter ? Color.mfPrimary.opacity(0.1) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer()
                }
                .frame(minWidth: 160, idealWidth: 200, maxWidth: 240)
                .background(Color.mfSurface)

                // Job Cards
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.jobs) { job in
                            TranscodeJobCardView(
                                job: job,
                                logMessages: viewModel.jobLogMessages[job.id] ?? [],
                                transferProgress: viewModel.jobTransferProgress[job.id],
                                onCancel: {
                                    Task { await viewModel.cancelJob(job.id) }
                                }
                            )
                        }

                        if viewModel.jobs.isEmpty && !viewModel.isLoading {
                            VStack(spacing: 12) {
                                Image(systemName: "tray")
                                    .font(.system(size: 40))
                                    .foregroundColor(.mfTextMuted)
                                Text("No jobs in queue")
                                    .font(.mfBody)
                                    .foregroundColor(.mfTextSecondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                        }
                    }
                    .padding(20)
                }
            }
        }
        .background(Color.mfBackground)
        .task {
            viewModel.connectWebSocket()
            await viewModel.loadJobs()
            await viewModel.loadQueueStats()
        }
    }
}
