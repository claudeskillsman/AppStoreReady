import Foundation

enum Endpoints {
    static let legacy = URL(string: "http://legacy.acme.com/feed")!
    static let reports = URL(string: "http://reports.acme-analytics.net/v1/upload")!
    static let local = URL(string: "http://localhost:8080")!
}
