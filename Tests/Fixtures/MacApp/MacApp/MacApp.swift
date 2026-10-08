import SwiftUI

@main
struct MacApp: App {
    @AppStorage("windowCount") private var windowCount = 1
    var body: some Scene { WindowGroup { Text("Mac").accessibilityLabel("Title") } }
}
