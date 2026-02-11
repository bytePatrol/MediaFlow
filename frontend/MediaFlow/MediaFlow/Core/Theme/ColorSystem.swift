import SwiftUI

extension Color {
    // Primary
    static let mfPrimary = Color(hex: "#256af4")
    static let mfPrimaryLight = Color(hex: "#4d8af7")
    static let mfPrimaryDark = Color(hex: "#1a4fc0")

    // Backgrounds
    static let mfBackground = Color(hex: "#101622")
    static let mfSurface = Color(hex: "#1a2234")
    static let mfSurfaceLight = Color(hex: "#1e293b")
    static let mfCard = Color(hex: "#1e293b")

    // Glass
    static let mfGlass = Color.white.opacity(0.03)
    static let mfGlassBorder = Color.white.opacity(0.08)

    // Status
    static let mfSuccess = Color(hex: "#22c55e")
    static let mfWarning = Color(hex: "#f59e0b")
    static let mfError = Color(hex: "#ef4444")
    static let mfInfo = Color(hex: "#3b82f6")

    // Quality Tiers
    static let mfQuality4K = Color(hex: "#3b82f6")
    static let mfQuality1080 = Color(hex: "#6366f1")
    static let mfQuality720 = Color(hex: "#64748b")
    static let mfQualitySD = Color(hex: "#ef4444")

    // Text
    static let mfTextPrimary = Color.white
    static let mfTextSecondary = Color(hex: "#94a3b8")
    static let mfTextMuted = Color(hex: "#64748b")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: hex)
        var rgbValue: UInt64 = 0
        scanner.scanHexInt64(&rgbValue)

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
