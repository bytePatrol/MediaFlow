import SwiftUI

struct LoadingSkeleton: View {
    @State private var isAnimating = false
    let width: CGFloat
    let height: CGFloat

    init(width: CGFloat = 100, height: CGFloat = 14) {
        self.width = width
        self.height = height
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(
                LinearGradient(
                    colors: [
                        Color.mfSurfaceLight,
                        Color.mfSurfaceLight.opacity(0.5),
                        Color.mfSurfaceLight,
                    ],
                    startPoint: isAnimating ? .leading : .trailing,
                    endPoint: isAnimating ? .trailing : .leading
                )
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}
