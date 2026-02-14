import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: 0) {
                SidebarView()
                    .frame(width: 200)

                Divider()

                Group {
                    switch appState.selectedNavItem {
                    case .library:
                        LibraryDashboardView()
                    case .quickTranscode:
                        QuickTranscodePageView()
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
                    case .help:
                        HelpView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.mfBackground)
            }

            // Global toast notifications
            VStack(spacing: 8) {
                ForEach(appState.toasts) { toast in
                    HStack(spacing: 10) {
                        Image(systemName: toast.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(toast.style.color)
                        Text(toast.message)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                appState.dismissToast(toast.id)
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.mfTextMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.mfSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(toast.style.color.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 240)
            .padding(.top, 12)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: appState.toasts.count)

            // Onboarding overlay
            if !appState.hasCompletedOnboarding {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .background(
            Group {
                Button("") { appState.selectedNavItem = .library }
                    .keyboardShortcut("1", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedNavItem = .quickTranscode }
                    .keyboardShortcut("2", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedNavItem = .processing }
                    .keyboardShortcut("3", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedNavItem = .servers }
                    .keyboardShortcut("4", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedNavItem = .analytics }
                    .keyboardShortcut("5", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedNavItem = .intelligence }
                    .keyboardShortcut("6", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedNavItem = .settings }
                    .keyboardShortcut("7", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedNavItem = .logs }
                    .keyboardShortcut("8", modifiers: .command)
                    .hidden()
                Button("") { appState.selectedNavItem = .help }
                    .keyboardShortcut("9", modifiers: .command)
                    .hidden()
            }
        )
    }
}
