import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var plexAuth = PlexAuthViewModel()
    @State private var step: Int = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    // Step content
                    Group {
                        switch step {
                        case 0: welcomeStep
                        case 1: connectPlexStep
                        case 2: addWorkerStep
                        case 3: readyStep
                        default: readyStep
                        }
                    }
                    .frame(maxWidth: 500)

                    // Navigation
                    HStack {
                        if step > 0 {
                            Button {
                                withAnimation { step -= 1 }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text("Back")
                                }
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.mfTextSecondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        // Progress dots
                        HStack(spacing: 6) {
                            ForEach(0..<4) { i in
                                Circle()
                                    .fill(i == step ? Color.mfPrimary : Color.mfSurfaceLight)
                                    .frame(width: 8, height: 8)
                            }
                        }

                        Spacer()

                        if step < 3 {
                            Button {
                                withAnimation { step += 1 }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("Next")
                                    Image(systemName: "chevron.right")
                                }
                                .primaryButton()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: 500)

                    // Skip button
                    Button {
                        appState.completeOnboarding()
                    } label: {
                        Text("Skip Setup")
                            .font(.system(size: 12))
                            .foregroundColor(.mfTextMuted)
                    }
                    .buttonStyle(.plain)
                }
                .padding(40)

                Spacer()
            }
        }
        .onChange(of: plexAuth.authState) { _, newState in
            if case .success = newState {
                Task {
                    let backend = BackendService()
                    appState.plexServers = (try? await backend.getPlexServers()) ?? []
                    appState.isConnected = !appState.plexServers.isEmpty
                }
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.mfPrimary)

            HStack(spacing: 0) {
                Text("Media")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)
                Text("Flow")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.mfPrimary)
            }

            Text("Optimize your Plex media library with intelligent transcoding, distributed GPU workers, and smart recommendations.")
                .font(.system(size: 14))
                .foregroundColor(.mfTextSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "brain", text: "AI-powered codec & quality recommendations")
                featureRow(icon: "server.rack", text: "Distributed transcoding across local & cloud GPUs")
                featureRow(icon: "chart.bar.xaxis", text: "Analytics dashboard with savings tracking")
                featureRow(icon: "bolt.fill", text: "One-click batch optimization")
            }
            .padding(.top, 8)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.mfPrimary)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.mfTextSecondary)
        }
    }

    private var connectPlexStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.badge.key")
                .font(.system(size: 48))
                .foregroundColor(.mfPrimary)

            Text("Connect to Plex")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            Text("Sign in with your Plex account to discover servers and sync your media library.")
                .font(.system(size: 14))
                .foregroundColor(.mfTextSecondary)
                .multilineTextAlignment(.center)

            // OAuth state
            Group {
                switch plexAuth.authState {
                case .idle:
                    Button {
                        plexAuth.startOAuthFlow()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "person.badge.key")
                            Text("Sign in with Plex")
                        }
                        .primaryButton()
                    }
                    .buttonStyle(.plain)

                case .creatingPin, .waitingForAuth:
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Waiting for authorization...")
                            .font(.mfBody)
                            .foregroundColor(.mfTextSecondary)
                    }

                case .success(let count):
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.mfSuccess)
                            .font(.system(size: 20))
                        Text("Connected! Found \(count) server\(count == 1 ? "" : "s").")
                            .font(.mfBody)
                            .foregroundColor(.mfSuccess)
                    }

                case .expired, .error:
                    VStack(spacing: 8) {
                        Text("Authentication failed. Please try again.")
                            .font(.mfCaption)
                            .foregroundColor(.mfError)
                        Button { plexAuth.startOAuthFlow() } label: {
                            Text("Retry").primaryButton()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var addWorkerStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 48))
                .foregroundColor(.mfPrimary)

            Text("Add a Worker")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            Text("Workers handle transcoding. You can add local, remote, or cloud GPU workers.")
                .font(.system(size: 14))
                .foregroundColor(.mfTextSecondary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: 16) {
                workerOption(icon: "desktopcomputer", title: "Local Worker", desc: "Use this Mac's CPU/GPU for transcoding")
                workerOption(icon: "network", title: "Remote Server", desc: "Connect to a remote machine via SSH")
                workerOption(icon: "cloud.bolt", title: "Cloud GPU", desc: "Deploy on-demand GPU instances (Vultr)")
            }
            .padding(.top, 8)

            Text("You can add workers later from the Servers page.")
                .font(.system(size: 11))
                .foregroundColor(.mfTextMuted)
        }
    }

    private func workerOption(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.mfPrimary)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.mfTextMuted)
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundColor(.mfSuccess)

            Text("You're Ready!")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.white)

            Text("Start by running an intelligence analysis to get personalized recommendations for your library.")
                .font(.system(size: 14))
                .foregroundColor(.mfTextSecondary)
                .multilineTextAlignment(.center)

            Button {
                appState.completeOnboarding()
                appState.selectedNavItem = .intelligence
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                    Text("Run Analysis")
                }
                .primaryButton()
            }
            .buttonStyle(.plain)

            Button {
                appState.completeOnboarding()
            } label: {
                Text("Go to Dashboard")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.mfPrimary)
            }
            .buttonStyle(.plain)
        }
    }
}
