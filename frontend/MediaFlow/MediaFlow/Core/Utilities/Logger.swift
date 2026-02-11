import Foundation
import os

enum MFLogger {
    private static let subsystem = "com.mediaflow.app"

    static let general = os.Logger(subsystem: subsystem, category: "general")
    static let network = os.Logger(subsystem: subsystem, category: "network")
    static let transcode = os.Logger(subsystem: subsystem, category: "transcode")
    static let plex = os.Logger(subsystem: subsystem, category: "plex")
}
