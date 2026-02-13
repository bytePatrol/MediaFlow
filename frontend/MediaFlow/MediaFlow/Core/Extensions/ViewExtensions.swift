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

    func hoverHighlight() -> some View {
        self.modifier(HoverHighlightModifier())
    }

    func hoverCard() -> some View {
        self.modifier(HoverCardModifier())
    }

    func pressEffect() -> some View {
        self.modifier(PressEffectModifier())
    }
}

struct HoverHighlightModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .brightness(isHovered ? 0.05 : 0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct HoverCardModifier: ViewModifier {
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(isHovered ? 0.3 : 0.1), radius: isHovered ? 12 : 4, y: isHovered ? 4 : 2)
            .brightness(isHovered ? 0.03 : 0)
            .animation(.easeOut(duration: 0.2), value: isHovered)
            .onHover { isHovered = $0 }
    }
}

struct PressEffectModifier: ViewModifier {
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in isPressed = true }
                    .onEnded { _ in isPressed = false }
            )
    }
}
