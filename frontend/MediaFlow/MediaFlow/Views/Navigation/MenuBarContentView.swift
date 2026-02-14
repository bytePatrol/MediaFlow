import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: TranscodeViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Circle()
                    .fill(appState.isBackendOnline ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(appState.isBackendOnline ? "Backend Connected" : "Backend Offline")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Active jobs
            if appState.activeJobCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(appState.activeJobCount) Active Job\(appState.activeJobCount == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)

                    ForEach(viewModel.jobs.filter { $0.isActive }.prefix(3), id: \.id) { job in
                        HStack(spacing: 8) {
                            Text(job.mediaTitle ?? job.sourcePath?.components(separatedBy: "/").last ?? "Job #\(job.id)")
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text("\(Int(job.progressPercent))%")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 6)

                Divider()
            } else {
                Text("No active jobs")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(12)

                Divider()
            }

            // Actions
            Button("Open MediaFlow") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title.contains("MediaFlow") || $0.isKeyWindow }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            Button("Quit MediaFlow") {
                NSApp.terminate(nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(width: 260)
    }
}
