import Foundation

extension Int {
    var formattedFileSize: String {
        let bytes = Double(self)
        let units = ["B", "KB", "MB", "GB", "TB"]
        var unitIndex = 0
        var size = bytes
        while size >= 1024 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        return String(format: "%.1f %@", size, units[unitIndex])
    }

    var formattedBitrate: String {
        let bps = Double(self)
        if bps >= 1_000_000 {
            return String(format: "%.1f Mbps", bps / 1_000_000)
        } else if bps >= 1_000 {
            return String(format: "%.0f Kbps", bps / 1_000)
        }
        return "\(self) bps"
    }

    var formattedDuration: String {
        let totalSeconds = self / 1000
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(String(format: "%02d", minutes))m"
        }
        let seconds = totalSeconds % 60
        return "\(minutes)m \(String(format: "%02d", seconds))s"
    }
}

extension Double {
    var formattedFPS: String {
        return String(format: "%.1f FPS", self)
    }

    var formattedPercent: String {
        return String(format: "%.1f%%", self)
    }
}

extension Optional where Wrapped == Int {
    var formattedFileSize: String {
        guard let value = self else { return "--" }
        return value.formattedFileSize
    }

    var formattedBitrate: String {
        guard let value = self else { return "--" }
        return value.formattedBitrate
    }
}
