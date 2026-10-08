import Foundation

struct Settings {
    var lastSync: Date? {
        UserDefaults.standard.object(forKey: "lastSync") as? Date
    }
}
