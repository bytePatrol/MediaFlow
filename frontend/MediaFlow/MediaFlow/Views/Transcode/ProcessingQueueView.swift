import SwiftUI

struct ProcessingQueueView: View {
    @EnvironmentObject var viewModel: TranscodeViewModel
    @State private var showClearConfirm = false
    @State private var showClearCacheConfirm = false
    @State private var showPauseConfirm = false
    @State private var cloudDeployPanel = CloudDeployPanel()
    @State private var queueStrategy: String = "default"
    @State private var isLoadingStrategy = false
    @State private var draggedJobId: Int?
    @State private var dropTargetJobId: Int?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            workerIssueBanner
            mainContent
        }
        .background(Color.mfBackground)
        .task {
            await viewModel.loadJobs()
            await viewModel.loadQueueStats()
            isLoadingStrategy = true
            do {
                let response = try await BackendService().getQueueStrategy()
                queueStrategy = response.strategy
            } catch {}
            isLoadingStrategy = false
        }
        .confirmationDialog("Clear all finished jobs?", isPresented: $showClearConfirm) {
            Button("Clear All", role: .destructive) {
                Task { await viewModel.clearFinished() }
            }
        } message: {
            Text("This will remove all completed, failed, and cancelled jobs from the queue.")
        }
        .confirmationDialog("Clear transcode cache?", isPresented: $showClearCacheConfirm) {
            Button("Clear Cache", role: .destructive) {
                Task { let _ = await viewModel.clearCache() }
            }
        } message: {
            Text("This will delete temporary transcode files from the working directory.")
        }
        .confirmationDialog("Pause all active jobs?", isPresented: $showPauseConfirm) {
            Button("Pause All", role: .destructive) {
                Task { await viewModel.pauseAll() }
            }
        } message: {
            Text("All currently transcoding jobs will be paused.")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
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

            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10))
                    .foregroundColor(.mfTextMuted)
                Picker("", selection: $queueStrategy) {
                    Text("First In, First Out").tag("default")
                    Text("Biggest Savings First").tag("biggest_savings")
                    Text("Fastest Jobs First").tag("fastest_first")
                    Text("Most Watched First").tag("most_watched")
                }
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: queueStrategy) { _, newStrategy in
                    guard !isLoadingStrategy else { return }
                    Task {
                        let service = BackendService()
                        let _ = try? await service.setQueueStrategy(newStrategy)
                    }
                }
            }
            .opacity(isLoadingStrategy ? 0.5 : 1.0)

            headerActions
        }
        .padding(20)
        .background(Color.mfSurface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .bottom)
    }

    private var headerActions: some View {
        HStack(spacing: 8) {
            Button {
                showClearConfirm = true
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
                showClearCacheConfirm = true
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
                showPauseConfirm = true
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

    // MARK: - Worker Issue Banner

    @ViewBuilder
    private var workerIssueBanner: some View {
        Group {
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
                    .transition(.opacity.combined(with: .move(edge: .top)))
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
                                cloudDeployPanel.show {
                                    viewModel.isDeployingCloud = true
                                }
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
                            Text("Go to Settings \u{2192} Servers to add or enable a worker.")
                                .font(.system(size: 11))
                                .foregroundColor(.mfTextMuted)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.mfWarning.opacity(0.08))
                    .overlay(Rectangle().frame(height: 1).foregroundColor(.mfWarning.opacity(0.2)), alignment: .bottom)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.hasWorkerIssue)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        HSplitView {
            sidebarFilters
            jobList
        }
    }

    private var sidebarFilters: some View {
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
    }

    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(nonQueuedJobs) { job in
                    TranscodeJobCardView(
                        job: job,
                        logMessages: viewModel.jobLogMessages[job.id] ?? [],
                        transferProgress: viewModel.jobTransferProgress[job.id],
                        preuploadProgress: viewModel.jobPreuploadProgress[job.id],
                        phaseLabel: viewModel.jobPhaseLabel[job.id],
                        onCancel: {
                            Task { await viewModel.cancelJob(job.id) }
                        }
                    )
                }

                queuedJobsSection

                if viewModel.jobs.isEmpty && !viewModel.isLoading {
                    EmptyStateView(
                        icon: "tray",
                        title: "No jobs in queue",
                        description: "Transcode jobs will appear here when you start processing."
                    )
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private var queuedJobsSection: some View {
        if !viewModel.queuedJobs.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.mfTextMuted)
                Text("QUEUED \u{2014} DRAG TO REORDER")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.mfTextMuted)
                    .tracking(1)
                Rectangle()
                    .fill(Color.mfGlassBorder)
                    .frame(height: 1)
            }
            .padding(.top, 8)

            ForEach(Array(viewModel.queuedJobs.enumerated()), id: \.element.id) { index, job in
                queuedJobRow(job: job, index: index)
            }
        }
    }

    private func queuedJobRow(job: TranscodeJob, index: Int) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.mfTextMuted)
                Text("#\(index + 1)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.mfPrimary)
            }
            .frame(width: 36)
            .padding(.vertical, 12)
            .contentShape(Rectangle())

            TranscodeJobCardView(
                job: job,
                logMessages: viewModel.jobLogMessages[job.id] ?? [],
                transferProgress: viewModel.jobTransferProgress[job.id],
                preuploadProgress: viewModel.jobPreuploadProgress[job.id],
                phaseLabel: viewModel.jobPhaseLabel[job.id],
                onCancel: {
                    Task { await viewModel.cancelJob(job.id) }
                }
            )
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(dropTargetJobId == job.id ? Color.mfPrimary : Color.clear, lineWidth: 2)
        )
        .draggable(String(job.id)) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 12))
                Text(job.mediaTitle ?? "Job #\(job.id)")
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.mfSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
            .onAppear { draggedJobId = job.id }
        }
        .dropDestination(for: String.self) { droppedStrings, _ in
            guard let idStr = droppedStrings.first,
                  let sourceId = Int(idStr) else { return false }
            reorderByDrop(sourceId: sourceId, targetId: job.id)
            dropTargetJobId = nil
            return true
        } isTargeted: { isTargeted in
            dropTargetJobId = isTargeted ? job.id : nil
        }
    }

    // MARK: - Helpers

    /// Jobs that are NOT queued (active, completed, failed, etc.) — shown above the reorderable section.
    private var nonQueuedJobs: [TranscodeJob] {
        viewModel.jobs.filter { $0.status != "queued" }
    }

    /// Handle a drag-and-drop reorder by moving sourceId to the position of targetId.
    private func reorderByDrop(sourceId: Int, targetId: Int) {
        guard sourceId != targetId else { return }
        var queued = viewModel.queuedJobs
        guard let sourceIndex = queued.firstIndex(where: { $0.id == sourceId }),
              let targetIndex = queued.firstIndex(where: { $0.id == targetId }) else { return }

        let movedJob = queued.remove(at: sourceIndex)
        queued.insert(movedJob, at: targetIndex)

        // Update priorities locally so the UI reflects immediately
        let maxPriority = queued.count
        for (i, job) in queued.enumerated() {
            if let idx = viewModel.jobs.firstIndex(where: { $0.id == job.id }) {
                viewModel.jobs[idx].priority = maxPriority - i
            }
        }

        // Persist to backend
        let orderedIds = queued.map { $0.id }
        Task {
            let _ = try? await BackendService().reorderQueue(jobIds: orderedIds)
        }
        draggedJobId = nil
    }
}
