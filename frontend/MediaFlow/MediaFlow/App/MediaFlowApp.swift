import SwiftUI
import AppKit

@main
struct MediaFlowApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var transcodeViewModel = TranscodeViewModel()

    init() {
        if let url = Bundle.module.url(forResource: "mediaflow-logo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(transcodeViewModel)
                .preferredColorScheme(.dark)
                .frame(minWidth: 900, minHeight: 500)
                .task {
                    transcodeViewModel.connectWebSocket()
                    await transcodeViewModel.loadJobs()
                    await transcodeViewModel.loadQueueStats()
                    await transcodeViewModel.loadCloudSettings()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1440, height: 900)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
