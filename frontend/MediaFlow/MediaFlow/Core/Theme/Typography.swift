import SwiftUI

extension Font {
    static let mfTitle = Font.system(size: 24, weight: .bold, design: .default)
    static let mfHeadline = Font.system(size: 18, weight: .bold, design: .default)
    static let mfSubheadline = Font.system(size: 14, weight: .semibold, design: .default)
    static let mfBody = Font.system(size: 13, weight: .regular, design: .default)
    static let mfBodyMedium = Font.system(size: 13, weight: .medium, design: .default)
    static let mfCaption = Font.system(size: 11, weight: .medium, design: .default)
    static let mfCaptionSmall = Font.system(size: 10, weight: .bold, design: .default)
    static let mfMono = Font.system(size: 12, weight: .regular, design: .monospaced)
    static let mfMonoSmall = Font.system(size: 10, weight: .medium, design: .monospaced)
    static let mfMonoLarge = Font.system(size: 14, weight: .semibold, design: .monospaced)
    static let mfLabel = Font.system(size: 10, weight: .bold, design: .default)
    static let mfMetric = Font.system(size: 28, weight: .bold, design: .default)
}

extension View {
    func mfSectionHeader() -> some View {
        self
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.mfTextMuted)
            .textCase(.uppercase)
            .tracking(1.5)
    }
}
