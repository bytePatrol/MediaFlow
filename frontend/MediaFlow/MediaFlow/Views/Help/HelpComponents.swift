import SwiftUI

// MARK: - HelpStepView

struct HelpStepView: View {
    let step: HelpStep

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(step.number)")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.mfPrimary)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.mfTextPrimary)
                Text(step.description)
                    .font(.mfBody)
                    .foregroundColor(.mfTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - HelpTipView

struct HelpTipView: View {
    let tip: HelpTip

    private var accentColor: Color {
        switch tip.style {
        case .info: return .mfInfo
        case .warning: return .mfWarning
        case .success: return .mfSuccess
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tip.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(accentColor)
                .frame(width: 18)

            Text(tip.text)
                .font(.mfBody)
                .foregroundColor(.mfTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(accentColor.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - HelpShortcutRow

struct HelpShortcutRow: View {
    let shortcut: HelpShortcut

    var body: some View {
        HStack(spacing: 12) {
            Text(shortcut.keys)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.mfTextPrimary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.mfSurfaceLight)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.mfGlassBorder, lineWidth: 1)
                )
                .frame(width: 64)

            Text(shortcut.description)
                .font(.mfBody)
                .foregroundColor(.mfTextSecondary)

            Spacer()
        }
    }
}

// MARK: - HelpTroubleshootCard

struct HelpTroubleshootCard: View {
    let item: TroubleshootItem
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.mfWarning)

                    Text(item.problem)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.mfTextPrimary)
                        .multilineTextAlignment(.leading)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.mfTextMuted)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(12)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .background(Color.mfGlassBorder)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("CAUSE")
                            .mfSectionHeader()
                        Text(item.cause)
                            .font(.mfBody)
                            .foregroundColor(.mfTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("SOLUTION")
                            .mfSectionHeader()
                        Text(item.solution)
                            .font(.mfBody)
                            .foregroundColor(.mfTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.mfGlassBorder, lineWidth: 1)
        )
    }
}

// MARK: - HelpFeatureRow

struct HelpFeatureRow: View {
    let feature: FeatureItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.mfPrimary)
                .frame(width: 32, height: 32)
                .background(Color.mfPrimary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.mfTextPrimary)
                Text(feature.description)
                    .font(.mfBody)
                    .foregroundColor(.mfTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
