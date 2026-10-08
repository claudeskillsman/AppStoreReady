import SwiftUI

@main
struct ValidAppApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        WindowGroup {
            Text(hasCompletedOnboarding ? "Welcome back" : "Welcome")
                .accessibilityLabel("Greeting")
        }
    }
}
