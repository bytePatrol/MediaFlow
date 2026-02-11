import SwiftUI

struct StatusIndicator: View {
    let status: String

    var color: Color {
        switch status.lowercased() {
        case "online", "connected", "completed", "healthy": return .mfSuccess
        case "offline", "disconnected", "failed", "error": return .mfError
        case "busy", "transcoding", "processing", "peak": return .mfWarning
        case "pending", "queued": return .mfInfo
        default: return .mfTextMuted
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.5), radius: 3)
            Text(status.capitalized)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(color)
        }
    }
}
