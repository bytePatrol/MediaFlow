import SwiftUI
import AppKit
import UserNotifications

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuObserver: Any?
    private var isStripping = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftUI recreates menus after launch, so observe and strip the
        // Help menu whenever it reappears (no Help Book is registered).
        stripHelpMenu()
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didAddItemNotification,
            object: NSApp.mainMenu,
            queue: .main
        ) { [weak self] _ in
            self?.stripHelpMenu()
        }
    }

    private func stripHelpMenu() {
        guard !isStripping, let mainMenu = NSApp.mainMenu else { return }
        isStripping = true
        mainMenu.items.removeAll { $0.title == "Help" }
        isStripping = false
    }
}

@main
struct MediaFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var transcodeViewModel = TranscodeViewModel()
    @StateObject private var processManager = BackendProcessManager.shared

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
            ZStack {
                if processManager.state.isReady {
                    ContentView()
                        .environmentObject(appState)
                        .environmentObject(transcodeViewModel)
                        .preferredColorScheme(.dark)
                        .frame(minWidth: 900, minHeight: 500)
                } else {
                    BackendStartupView(processManager: processManager)
                        .frame(minWidth: 900, minHeight: 500)
                }
            }
            .preferredColorScheme(.dark)
            .task {
                await processManager.startBackend()
                appState.backendURL = processManager.backendURL
                let wsURL = processManager.backendURL
                    .replacingOccurrences(of: "http://", with: "ws://")
                    .replacingOccurrences(of: "https://", with: "wss://")
                    + "/ws"
                transcodeViewModel.updateBackendURL(processManager.backendURL)
                transcodeViewModel.connectWebSocket(url: wsURL)
                await transcodeViewModel.loadJobs()
                await transcodeViewModel.loadQueueStats()
                await transcodeViewModel.loadCloudSettings()
            }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(replacing: .help) { }
        }

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
