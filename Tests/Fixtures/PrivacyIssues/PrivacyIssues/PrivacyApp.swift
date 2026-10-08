import SwiftUI

@main
struct PrivacyApp: App {
    @AppStorage("launches") private var launches = 0
    private let started = ProcessInfo.processInfo.systemUptime

    var body: some Scene { WindowGroup { Text("Privacy").accessibilityLabel("Title") } }
}
