import SwiftUI

struct StatisticsCardView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    var trend: String? = nil
    var trendUp: Bool = true
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .padding(8)
                    .background(iconColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Spacer()

                if let trend = trend {
                    HStack(spacing: 2) {
                        Image(systemName: trendUp ? "arrow.up" : "arrow.down")
                            .font(.system(size: 9))
                        Text(trend)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(trendUp ? .mfSuccess : .mfError)
                }

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.mfTextMuted)
                }
            }

            Text(title)
                .font(.mfCaption)
                .foregroundColor(.mfTextSecondary)

            Text(value)
                .font(.system(size: 28, weight: .bold))
        }
        .padding(20)
        .cardStyle()
    }
}
