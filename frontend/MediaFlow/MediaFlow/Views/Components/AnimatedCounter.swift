import SwiftUI

struct AnimatedCounter: View {
    let value: Double
    let format: String
    let duration: Double

    @State private var displayValue: Double = 0
    @State private var hasAnimated = false

    init(value: Double, format: String = "%.0f", duration: Double = 1.2) {
        self.value = value
        self.format = format
        self.duration = duration
    }

    var body: some View {
        Text(String(format: format, displayValue))
            .onAppear {
                guard !hasAnimated else { return }
                hasAnimated = true
                withAnimation(.easeOut(duration: duration)) {
                    displayValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.easeOut(duration: 0.6)) {
                    displayValue = newValue
                }
            }
    }
}

struct AnimatedFileSizeCounter: View {
    let bytes: Int
    let duration: Double

    @State private var displayBytes: Double = 0
    @State private var hasAnimated = false

    init(bytes: Int, duration: Double = 1.2) {
        self.bytes = bytes
        self.duration = duration
    }

    var body: some View {
        Text(formattedSize)
            .onAppear {
                guard !hasAnimated else { return }
                hasAnimated = true
                withAnimation(.easeOut(duration: duration)) {
                    displayBytes = Double(bytes)
                }
            }
            .onChange(of: bytes) { _, newValue in
                withAnimation(.easeOut(duration: 0.6)) {
                    displayBytes = Double(newValue)
                }
            }
    }

    private var formattedSize: String {
        let b = displayBytes
        let units = ["B", "KB", "MB", "GB", "TB"]
        var unitIndex = 0
        var size = b
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        return String(format: "%.1f %@", size, units[unitIndex])
    }
}

struct AnimatedPercentCounter: View {
    let value: Double
    let duration: Double

    @State private var displayValue: Double = 0
    @State private var hasAnimated = false

    init(value: Double, duration: Double = 1.2) {
        self.value = value
        self.duration = duration
    }

    var body: some View {
        Text(String(format: "%.1f%%", displayValue))
            .onAppear {
                guard !hasAnimated else { return }
                hasAnimated = true
                withAnimation(.easeOut(duration: duration)) {
                    displayValue = value
                }
            }
            .onChange(of: value) { _, newValue in
                withAnimation(.easeOut(duration: 0.6)) {
                    displayValue = newValue
                }
            }
    }
}
