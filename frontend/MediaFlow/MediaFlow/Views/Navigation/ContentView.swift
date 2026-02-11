import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 200)

            Divider()

            Group {
                switch appState.selectedNavItem {
                case .library:
                    LibraryDashboardView()
                case .processing:
                    ProcessingQueueView()
                case .servers:
                    ServerManagementView()
                case .analytics:
                    AnalyticsDashboardView()
                case .intelligence:
                    RecommendationsView()
                case .settings:
                    SettingsView()
                case .logs:
                    LogsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.mfBackground)
        }
    }
}
