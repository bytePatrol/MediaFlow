import Foundation

struct TranscodePreset: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    var description: String?
    var isBuiltin: Bool = false
    var videoCodec: String = "libx265"
    var targetResolution: String?
    var bitrateMode: String = "crf"
    var crfValue: Int?
    var targetBitrate: String?
    var hwAccel: String?
    var audioMode: String = "copy"
    var audioCodec: String?
    var container: String = "mkv"
    var subtitleMode: String = "copy"
    var customFlags: String?
    var hdrMode: String = "preserve"
    var twoPass: Bool = false
    var encoderTune: String?

    var iconName: String {
        switch name {
        case "Balanced": return "slider.horizontal.3"
        case "Storage Saver": return "arrow.down.doc"
        case "Mobile Optimized": return "iphone"
        case "Ultra Fidelity": return "star"
        default: return "gearshape"
        }
    }
}
