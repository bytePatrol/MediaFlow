import SwiftUI

struct ProcessingQueueView: View {
    @EnvironmentObject var viewModel: TranscodeViewModel

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
                                .fill(viewModel.queueStatusColor)
                                .frame(width: 6, height: 6)
                            Text(viewModel.queueStatusLabel)
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

            // No workers warning / cloud deploy banner
            if viewModel.hasWorkerIssue {
                if viewModel.isDeployingCloud {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                        Text("Cloud GPU is building — queued jobs will start automatically when ready.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.mfPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.mfPrimary.opacity(0.08))
                    .overlay(Rectangle().frame(height: 1).foregroundColor(.mfPrimary.opacity(0.2)), alignment: .bottom)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.mfWarning)
                        Text("No worker servers are online — queued jobs cannot be processed.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.mfWarning)
                        Spacer()
                        if viewModel.cloudApiKeyConfigured {
                            Button {
                                Task { await viewModel.deployCloudGPU() }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "cloud.bolt.fill")
                                        .font(.system(size: 11))
                                    Text("Deploy Cloud GPU")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.mfPrimary)
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("Go to Settings → Servers to add or enable a worker.")
                                .font(.system(size: 11))
                                .foregroundColor(.mfTextMuted)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.mfWarning.opacity(0.08))
                    .overlay(Rectangle().frame(height: 1).foregroundColor(.mfWarning.opacity(0.2)), alignment: .bottom)
                }
            }

            // Quick Transcode section
            ManualTranscodeView()
                .environmentObject(viewModel)

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
                                phaseLabel: viewModel.jobPhaseLabel[job.id],
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
            // Refresh on tab switch — WebSocket keeps state alive between visits
            await viewModel.loadJobs()
            await viewModel.loadQueueStats()
        }
    }
}
