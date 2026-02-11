import Foundation

struct AppSettings: Codable {
    var backendUrl: String = "http://localhost:9876"
    var plexUrl: String = ""
    var plexToken: String = ""
    var defaultPresetId: Int?
    var autoSync: Bool = true
    var syncInterval: Int = 3600
    var notificationsEnabled: Bool = true
    var theme: String = "dark"
}
