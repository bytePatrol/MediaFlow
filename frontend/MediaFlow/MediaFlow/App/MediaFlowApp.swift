import SwiftUI
import AppKit
import UserNotifications

@main
struct MediaFlowApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var transcodeViewModel = TranscodeViewModel()

    init() {
        if let url = Bundle.module.url(forResource: "mediaflow-logo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = image
        }

        // Set up local notification delegate and request permission
        // Guard: UNUserNotificationCenter crashes in SPM builds without a bundle identifier
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = NotificationService.shared
        }
        NotificationService.shared.requestPermission()
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

        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appState)
                .environmentObject(transcodeViewModel)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.circle.fill")
                if appState.activeJobCount > 0 {
                    Text("\(appState.activeJobCount)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
