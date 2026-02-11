import SwiftUI

struct QualityBadge: View {
    let resolution: String
    let isHdr: Bool

    var body: some View {
        Text(badgeText)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(badgeColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(badgeColor.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(badgeColor.opacity(0.2), lineWidth: 1)
            )
    }

    private var badgeText: String {
        if resolution == "4K" && isHdr { return "4K HDR" }
        if resolution == "4K" { return "4K" }
        return resolution
    }

    private var badgeColor: Color {
        switch resolution {
        case "4K": return .mfQuality4K
        case "1080p": return .mfQuality1080
        case "720p": return .mfQuality720
        case "480p", "SD": return .mfQualitySD
        default: return .mfTextMuted
        }
    }
}
