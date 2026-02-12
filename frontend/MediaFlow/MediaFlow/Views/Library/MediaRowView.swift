import SwiftUI

struct MediaRowView: View {
    let item: MediaItem
    let isSelected: Bool
    @ObservedObject var columnConfig: ColumnConfig
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundColor(isSelected ? .mfPrimary : .mfTextMuted)
            }
            .buttonStyle(.plain)
            .frame(width: 32)

            // Title + Year + Duration (+ file size when column hidden)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let year = item.year {
                        Text("\(year)")
                    }
                    Text("•")
                    Text(item.formattedDuration)
                    if !columnConfig.isVisible(.fileSize), let size = item.fileSize {
                        Text("•")
                        Text(size.formattedFileSize)
                    }

                    if let tags = item.tags, !tags.isEmpty {
                        Text("•")
                        ForEach(tags) { tag in
                            Text(tag.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color(hex: tag.color).opacity(0.7))
                                .clipShape(Capsule())
                        }
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.mfTextMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)

            // Dynamic columns (12pt spacer matches header divider handle width)
            ForEach(columnConfig.visibleColumns) { column in
                Spacer().frame(width: 12)
                columnCell(for: column)
                    .frame(width: columnConfig.width(for: column) - 12, alignment: .leading)
            }

            // Spacer for the gear icon column
            Spacer().frame(width: 24)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.mfPrimary.opacity(0.05) : Color.clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func columnCell(for column: TableColumn) -> some View {
        switch column {
        case .fileSize:
            Text(item.formattedFileSize)
                .font(.mfMono)
                .foregroundColor(.mfTextSecondary)
                .lineLimit(1)

        case .resolution:
            QualityBadge(resolution: item.resolutionTier ?? "Unknown", isHdr: item.isHdr)

        case .codec:
            Text(item.codecDisplayName)
                .font(.mfMono)
                .foregroundColor(.mfTextSecondary)
                .lineLimit(1)

        case .bitrate:
            HStack(spacing: 2) {
                Text(item.formattedBitrate)
                    .font(.mfMono)
                    .foregroundColor(.white)
                Text("Mbps")
                    .font(.mfMonoSmall)
                    .foregroundColor(.mfTextMuted)
            }

        case .audio:
            Text(item.audioDisplayName)
                .font(.system(size: 10))
                .foregroundColor(.mfTextSecondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.mfSurface)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .lineLimit(1)
        }
    }
}
