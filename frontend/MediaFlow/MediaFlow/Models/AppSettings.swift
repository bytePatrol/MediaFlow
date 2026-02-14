import Foundation

struct AppSettings: Codable {
    var backendUrl: String = BackendService.defaultBaseURL
    var plexUrl: String = ""
    var plexToken: String = ""
    var defaultPresetId: Int?
    var autoSync: Bool = true
    var syncInterval: Int = 3600
    var notificationsEnabled: Bool = true
    var theme: String = "dark"
}
