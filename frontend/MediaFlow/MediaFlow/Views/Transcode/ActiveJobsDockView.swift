import SwiftUI

struct ActiveJobsDockView: View {
    let activeJobCount: Int
    let aggregateFPS: Double
    let currentJobTitle: String?
    let currentJobProgress: Double

    var body: some View {
        HStack(spacing: 12) {
            // Pulsing dot + count
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.mfPrimary)
                    .frame(width: 6, height: 6)
                    .shadow(color: .mfPrimary.opacity(0.5), radius: 4)

                Text("ACTIVE JOBS (\(activeJobCount))")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
            }

            Divider()
                .frame(height: 16)

            // Current job mini-progress
            if let title = currentJobTitle {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Transcoding: \(title)")
                            .font(.system(size: 9))
                            .foregroundColor(.mfTextSecondary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(currentJobProgress))%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.mfPrimary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.mfSurface)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.mfPrimary)
                                .frame(width: geo.size.width * currentJobProgress / 100)
                                .shadow(color: .mfPrimary.opacity(0.5), radius: 4)
                        }
                    }
                    .frame(width: 180, height: 3)
                }
            }

            Spacer()

            // Stats
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 11))
                    Text(String(format: "%.1f FPS", aggregateFPS))
                        .font(.mfMonoSmall)
                }
                .foregroundColor(.mfTextSecondary)

                Button {
                } label: {
                    Text("VIEW DETAILED LOGS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfPrimary)
                        .tracking(0.5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(Color.mfSurface)
        .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .top)
    }
}
