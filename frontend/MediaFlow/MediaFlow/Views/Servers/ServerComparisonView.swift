import SwiftUI

struct ServerComparisonView: View {
    let servers: [WorkerServer]
    let metrics: [Int: ServerStatus]
    let benchmarks: [Int: BenchmarkResult]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundColor(.mfPrimary)
                    Text("Server Comparison")
                        .font(.system(size: 18, weight: .bold))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.mfTextSecondary)
                        .padding(6)
                        .background(Color.mfSurfaceLight)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder), alignment: .bottom)

            ScrollView {
                VStack(spacing: 0) {
                    // Table header
                    comparisonRow(
                        cells: [
                            ("Server", nil),
                            ("Status", nil),
                            ("Perf Score", nil),
                            ("CPU", nil),
                            ("GPU", nil),
                            ("Upload", nil),
                            ("Download", nil),
                            ("Active Jobs", nil),
                            ("RAM", nil),
                        ],
                        isHeader: true
                    )

                    ForEach(servers) { server in
                        let m = metrics[server.id]
                        let b = benchmarks[server.id]

                        comparisonRow(
                            cells: [
                                (server.name, nil),
                                (server.status.capitalized, statusColor(server.status)),
                                (server.performanceScore.map { "\(Int($0))" } ?? "--", scoreColor(server.performanceScore)),
                                (server.cpuModel ?? "--", nil),
                                (server.gpuModel ?? "--", nil),
                                (b?.uploadMbps.map { String(format: "%.0f Mbps", $0) } ?? "--", nil),
                                (b?.downloadMbps.map { String(format: "%.0f Mbps", $0) } ?? "--", nil),
                                ("\(m?.activeJobs ?? 0) / \(server.maxConcurrentJobs)", nil),
                                (server.ramGb.map { "\(Int($0)) GB" } ?? "--", nil),
                            ],
                            isHeader: false
                        )
                    }
                }
                .padding(24)
            }
        }
        .background(Color.mfBackground)
    }

    @ViewBuilder
    private func comparisonRow(cells: [(String, Color?)], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                Text(cell.0)
                    .font(isHeader
                        ? .system(size: 10, weight: .bold)
                        : .system(size: 12, weight: .medium))
                    .foregroundColor(cell.1 ?? (isHeader ? .mfTextMuted : .primary))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : .center)
                    .padding(.vertical, isHeader ? 10 : 12)
                    .padding(.horizontal, 8)
            }
        }
        .background(isHeader ? Color.mfSurfaceLight.opacity(0.5) : Color.clear)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(.mfGlassBorder.opacity(0.3)),
            alignment: .bottom
        )
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "online": return .mfSuccess
        case "offline": return .mfError
        default: return .mfWarning
        }
    }

    private func scoreColor(_ score: Double?) -> Color? {
        guard let s = score else { return nil }
        if s >= 75 { return .mfSuccess }
        if s >= 40 { return .mfWarning }
        return .mfError
    }
}
