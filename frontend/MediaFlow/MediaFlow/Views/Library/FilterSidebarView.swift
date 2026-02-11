import SwiftUI

struct FilterSidebarView: View {
    @ObservedObject var filterState: FilterState
    let onApply: () -> Void

    let resolutionOptions = ["4K", "1080p", "720p", "480p", "SD"]
    let codecOptions = ["hevc", "h264", "av1", "vc1", "mpeg4"]
    let codecLabels = ["hevc": "HEVC (H.265)", "h264": "AVC (H.264)", "av1": "AV1", "vc1": "VC-1", "mpeg4": "MPEG-4"]
    let audioOptions = ["truehd", "dts", "ac3", "eac3", "aac", "flac"]
    let audioLabels = ["truehd": "TrueHD", "dts": "DTS-HD", "ac3": "AC3", "eac3": "EAC3", "aac": "AAC", "flac": "FLAC"]

    @State private var bitrateRange: ClosedRange<Double> = 0...80

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Resolution
                    FilterSection(title: "Resolution") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(resolutionOptions, id: \.self) { res in
                                FilterCheckbox(
                                    label: res == "4K" ? "4K Ultra HD" : res == "1080p" ? "1080p Full HD" : res == "720p" ? "720p HD" : res,
                                    isChecked: filterState.resolutions.contains(res)
                                ) {
                                    if filterState.resolutions.contains(res) {
                                        filterState.resolutions.remove(res)
                                    } else {
                                        filterState.resolutions.insert(res)
                                    }
                                }
                            }
                        }
                    }

                    // Video Codec
                    FilterSection(title: "Video Codec") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(codecOptions, id: \.self) { codec in
                                FilterCheckbox(
                                    label: codecLabels[codec] ?? codec,
                                    isChecked: filterState.videoCodecs.contains(codec)
                                ) {
                                    if filterState.videoCodecs.contains(codec) {
                                        filterState.videoCodecs.remove(codec)
                                    } else {
                                        filterState.videoCodecs.insert(codec)
                                    }
                                }
                            }
                        }
                    }

                    // Bitrate Range
                    FilterSection(title: "Bitrate (Mbps)") {
                        VStack(spacing: 8) {
                            HStack {
                                Text("\(Int(bitrateRange.lowerBound))")
                                    .font(.mfMonoSmall)
                                    .foregroundColor(.mfPrimary)
                                Text("-")
                                    .foregroundColor(.mfTextMuted)
                                Text("\(Int(bitrateRange.upperBound))")
                                    .font(.mfMonoSmall)
                                    .foregroundColor(.mfPrimary)
                                Spacer()
                            }

                            HStack(spacing: 8) {
                                Slider(value: Binding(
                                    get: { bitrateRange.lowerBound },
                                    set: { bitrateRange = $0...bitrateRange.upperBound }
                                ), in: 0...80)
                                Slider(value: Binding(
                                    get: { bitrateRange.upperBound },
                                    set: { bitrateRange = bitrateRange.lowerBound...$0 }
                                ), in: 0...80)
                            }
                            .tint(.mfPrimary)
                        }
                    }

                    // Audio Format
                    FilterSection(title: "Audio Format") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(audioOptions, id: \.self) { audio in
                                Button {
                                    if filterState.audioCodecs.contains(audio) {
                                        filterState.audioCodecs.remove(audio)
                                    } else {
                                        filterState.audioCodecs.insert(audio)
                                    }
                                } label: {
                                    Text(audioLabels[audio] ?? audio)
                                        .font(.system(size: 11))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 8)
                                        .background(filterState.audioCodecs.contains(audio) ? Color.mfPrimary.opacity(0.2) : Color.mfSurface)
                                        .foregroundColor(filterState.audioCodecs.contains(audio) ? .mfPrimary : .mfTextSecondary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(filterState.audioCodecs.contains(audio) ? Color.mfPrimary.opacity(0.5) : Color.mfGlassBorder, lineWidth: 1)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // HDR Toggle
                    FilterSection(title: "HDR") {
                        Toggle("HDR Content Only", isOn: $filterState.hdrOnly)
                            .font(.system(size: 12))
                            .tint(.mfPrimary)
                    }
                }
                .padding(20)
            }

            // Apply Button
            VStack {
                Divider().background(Color.mfGlassBorder)
                Button(action: onApply) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 12))
                        Text("Apply Filters")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .primaryButton()
                }
                .buttonStyle(.plain)
                .padding(16)
            }
        }
        .background(Color.mfSurface)
    }
}

struct FilterSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .mfSectionHeader()
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.mfTextMuted)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
            }
        }
    }
}

struct FilterCheckbox: View {
    let label: String
    let isChecked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 13))
                    .foregroundColor(isChecked ? .mfPrimary : .mfTextMuted)
                Text(label)
                    .font(.system(size: 12))
                    .foregroundColor(.mfTextPrimary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }
}
