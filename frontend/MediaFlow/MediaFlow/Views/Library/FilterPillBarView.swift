import SwiftUI

struct FilterPillBarView: View {
    @ObservedObject var filterState: FilterState
    let onApply: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Active Filters:")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.mfTextMuted)
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(filterState.activePills) { pill in
                        HStack(spacing: 4) {
                            Text("\(pill.category): \(pill.value)")
                                .font(.system(size: 11))
                                .foregroundColor(.mfPrimary)

                            Button {
                                pill.clearAction()
                                onApply()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.mfPrimary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.mfPrimary.opacity(0.1))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.mfPrimary.opacity(0.3), lineWidth: 1))
                        .hoverHighlight()
                    }

                    Button {
                        filterState.clear()
                        onApply()
                    } label: {
                        Text("Clear All")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.mfTextMuted)
                            .textCase(.uppercase)
                            .tracking(1)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.mfSurface)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.mfGlassBorder),
            alignment: .bottom
        )
    }
}
