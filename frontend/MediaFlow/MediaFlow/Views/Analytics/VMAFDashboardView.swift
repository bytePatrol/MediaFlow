import SwiftUI

struct VMAFDashboardView: View {
    let stats: VMAFStatsResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quality Validation (VMAF)")
                        .font(.system(size: 16, weight: .bold))
                    Text("Perceptual quality scores for transcoded media")
                        .font(.system(size: 12))
                        .foregroundColor(.mfTextSecondary)
                }
                Spacer()
                if let avg = stats.avgScore {
                    VStack(spacing: 2) {
                        Text(String(format: "%.1f", avg))
                            .font(.system(size: 24, weight: .black))
                            .foregroundColor(vmafColor(avg))
                        Text("Avg VMAF")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.mfTextMuted)
                    }
                    .frame(width: 70, height: 60)
                    .background(vmafColor(avg).opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            // KPI row
            HStack(spacing: 12) {
                VMAFKPICard(title: "Scored", value: "\(stats.totalScored)", icon: "checkmark.circle", color: .mfPrimary)
                if let min = stats.minScore {
                    VMAFKPICard(title: "Min", value: String(format: "%.1f", min), icon: "arrow.down", color: vmafColor(min))
                }
                if let max = stats.maxScore {
                    VMAFKPICard(title: "Max", value: String(format: "%.1f", max), icon: "arrow.up", color: vmafColor(max))
                }
            }

            // By codec pair
            if !stats.byCodec.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quality by Codec Pair")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.mfTextSecondary)

                    ForEach(stats.byCodec) { entry in
                        HStack {
                            HStack(spacing: 4) {
                                Text(entry.sourceCodec.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.mfTextSecondary)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundColor(.mfTextMuted)
                                Text(entry.targetCodec.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.mfSuccess)
                            }
                            .frame(width: 120, alignment: .leading)

                            if let avg = entry.avgVmaf {
                                // VMAF bar
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(Color.mfSurfaceLight)
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(vmafColor(avg))
                                            .frame(width: geo.size.width * min(1, avg / 100))
                                    }
                                }
                                .frame(height: 8)

                                Text(String(format: "%.1f", avg))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(vmafColor(avg))
                                    .frame(width: 40, alignment: .trailing)
                            }

                            Text("\(entry.jobs) jobs")
                                .font(.system(size: 9))
                                .foregroundColor(.mfTextMuted)
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                }
                .padding(16)
                .background(Color.mfSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func vmafColor(_ score: Double) -> Color {
        if score >= 95 { return .mfSuccess }
        if score >= 90 { return .mfInfo }
        if score >= 80 { return .mfWarning }
        return .mfError
    }
}

struct VMAFKPICard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.mfTextMuted)
            }
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.mfTextPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.mfSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
