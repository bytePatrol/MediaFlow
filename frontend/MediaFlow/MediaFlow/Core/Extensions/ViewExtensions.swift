import SwiftUI

extension View {
    func glassPanel(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(Color.mfGlass)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.mfGlassBorder, lineWidth: 1)
            )
    }

    func cardStyle(cornerRadius: CGFloat = 12) -> some View {
        self
            .background(Color.mfSurface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.mfPrimary.opacity(0.1), lineWidth: 1)
            )
    }

    func primaryButton() -> some View {
        self
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.mfPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: Color.mfPrimary.opacity(0.3), radius: 8, y: 2)
    }

    func secondaryButton() -> some View {
        self
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.mfTextPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.mfSurfaceLight)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.mfGlassBorder, lineWidth: 1)
            )
    }
}
