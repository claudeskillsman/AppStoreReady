import StoreKit
import SwiftUI

@main
struct MultiplatformApp: App {
    @Environment(\.requestReview) private var requestReview
    var body: some Scene { WindowGroup { Button("Rate") { requestReview() }.accessibilityLabel("Rate the app") } }
}
