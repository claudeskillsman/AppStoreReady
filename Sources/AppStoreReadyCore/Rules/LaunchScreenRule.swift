import Foundation

/// ASR011: iOS apps need a launch screen.
public struct LaunchScreenRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR011",
        title: "Launch screen",
        description: "Checks that each iOS app declares a launch screen (UILaunchStoryboardName or UILaunchScreen, including Xcode's generated launch screen) and that a referenced launch storyboard exists in the project.",
        rationale: "Apple's documentation states that every iOS app must provide a launch screen, which the system shows while the app launches.",
        category: .appConfiguration,
        references: [
            Reference("Specifying your app’s launch screen", "https://developer.apple.com/documentation/xcode/specifying-your-apps-launch-screen"),
            Reference("UILaunchScreen", "https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchscreen"),
            Reference("UILaunchStoryboardName", "https://developer.apple.com/documentation/bundleresources/information-property-list/uilaunchstoryboardname"),
        ]
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.filter { ($0.productType == .application || $0.productType == .appClip) && $0.isIOS }.compactMap { target in
            guard let info = target.infoPlist, !info.isUnreadable else { return nil }
            let storyboard = info.string("UILaunchStoryboardName")?.trimmingCharacters(in: .whitespaces) ?? ""
            let hasLaunchScreenDictionary = info.resolved["UILaunchScreen"] != nil
                || info.resolved["UILaunchScreens"] != nil
                || info.resolved["UILaunchScreen_Generation"]?.boolValue == true

            if !storyboard.isEmpty {
                let file = context.infoPlistLocation(for: target, key: "UILaunchStoryboardName")
                let candidates = Set([storyboard + ".storyboard", storyboard + ".xib", storyboard])
                let found = context.allFilePaths.first { candidates.contains(($0 as NSString).lastPathComponent) }
                guard let found else {
                    return finding(
                        "Launch storyboard not found",
                        message: "'\(target.name)' names launch storyboard '\(storyboard)', but no \(storyboard).storyboard was found in the project.",
                        severity: .warning,
                        confidence: .medium,
                        classification: .potentialIssue,
                        file: file,
                        target: target,
                        evidence: ["UILaunchStoryboardName = \(storyboard)"],
                        fix: "Add the storyboard to the target, or correct UILaunchStoryboardName (Launch Screen File in the target's General settings)."
                    )
                }
                return finding(
                    "Launch screen configured",
                    message: "'\(target.name)' uses launch storyboard '\(storyboard)'.",
                    severity: .pass,
                    confidence: .high,
                    file: found,
                    target: target,
                    evidence: ["UILaunchStoryboardName = \(storyboard)"]
                )
            }
            if hasLaunchScreenDictionary {
                return finding(
                    "Launch screen configured",
                    message: "'\(target.name)' declares a launch screen with UILaunchScreen.",
                    severity: .pass,
                    confidence: .high,
                    file: context.infoPlistLocation(for: target, key: "UILaunchScreen"),
                    target: target
                )
            }
            return finding(
                "Missing launch screen",
                message: "'\(target.name)' declares neither UILaunchStoryboardName nor UILaunchScreen.",
                severity: .error,
                confidence: .high,
                classification: .verifiedIssue,
                file: context.infoPlistLocation(for: target, key: "UILaunchScreen"),
                target: target,
                fix: "Add a launch screen: set Launch Screen File in the target's General settings, or add a UILaunchScreen dictionary to Info.plist (INFOPLIST_KEY_UILaunchScreen_Generation = YES for generated Info.plists)."
            )
        }
    }
}
