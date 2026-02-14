import SwiftUI

struct BackendStartupView: View {
    @ObservedObject var processManager: BackendProcessManager

    var body: some View {
        ZStack {
            Color.mfBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                if let logoURL = Bundle.module.url(forResource: "mediaflow-logo", withExtension: "png"),
                   let nsImage = NSImage(contentsOf: logoURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                }

                switch processManager.state {
                case .idle, .starting:
                    VStack(spacing: 12) {
                        Text("Starting MediaFlow...")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)

                        Text("Launching backend server")
                            .font(.system(size: 12))
                            .foregroundColor(.mfTextMuted)
                    }

                case .failed(let message):
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.mfError)

                        Text("Failed to Start")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)

                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.mfTextMuted)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 300)

                        Button {
                            Task { await processManager.retry() }
                        } label: {
                            Text("Retry")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 8)
                                .background(Color.mfPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                case .running:
                    EmptyView()
                }
            }
        }
    }
}
