import Foundation

/// ASR024: App Store metadata that lives in the project, plus a reminder for
/// metadata that only exists in App Store Connect.
public struct AppStoreMetadataRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR024",
        title: "App Store metadata",
        description: "Checks the macOS app category (LSApplicationCategoryType) against Apple's documented values, and lists App Store Connect metadata that cannot be checked from the project: the privacy policy link, App Privacy details, and review notes.",
        rationale: "Apple's documentation says that for macOS apps you also set a category in the project. Guideline 5.1.1(i) requires a privacy policy link in App Store Connect and in the app, and Guideline 2.1 asks for complete metadata and a demo account when the app has a login; none of this can be verified from source.",
        category: .appStoreMetadata,
        references: [
            Reference("LSApplicationCategoryType", "https://developer.apple.com/documentation/bundleresources/information-property-list/lsapplicationcategorytype"),
            Reference("Preparing your app for distribution", "https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution"),
            Reference("App Review Guideline 5.1.1", "https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage"),
            Reference("App Review Guideline 2.1", "https://developer.apple.com/app-store/review/guidelines/#app-completeness"),
        ]
    )

    /// Values listed on the LSApplicationCategoryType page (retrieved 2026-10-08).
    static let categories: Set<String> = Set([
        "action-games", "adventure-games", "arcade-games", "board-games", "business", "card-games",
        "casino-games", "developer-tools", "dice-games", "education", "educational-games", "entertainment",
        "family-games", "finance", "games", "graphics-design", "healthcare-fitness", "kids-games", "lifestyle",
        "medical", "music", "music-games", "news", "photography", "productivity", "puzzle-games",
        "racing-games", "reference", "role-playing-games", "simulation-games", "social-networking", "sports",
        "sports-games", "strategy-games", "travel", "trivia-games", "utilities", "video", "weather", "word-games",
    ].map { "public.app-category." + $0 })

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        var findings: [Finding] = []
        let apps = context.targets.filter { $0.productType == .application }

        for target in apps where target.sdk.hasPrefix("macosx") {
            guard let info = target.infoPlist, !info.isUnreadable else { continue }
            let file = context.infoPlistLocation(for: target, key: "LSApplicationCategoryType")
            let value = info.string("LSApplicationCategoryType")?.trimmingCharacters(in: .whitespaces) ?? ""
            if value.isEmpty {
                findings.append(finding(
                    "Mac app category not set",
                    message: "'\(target.name)' does not set LSApplicationCategoryType. Apple's documentation says that for macOS apps you also set a category in your project.",
                    severity: .info,
                    confidence: .high,
                    classification: .bestPractice,
                    file: file,
                    target: target,
                    fix: "Choose an App Category in the target's General settings (LSApplicationCategoryType)."
                ))
            } else if !Self.categories.contains(value) {
                findings.append(finding(
                    "Unknown Mac app category",
                    message: "'\(target.name)' sets LSApplicationCategoryType to a value that is not in Apple's list of categories.",
                    severity: .warning,
                    confidence: .high,
                    classification: .verifiedIssue,
                    file: file,
                    target: target,
                    evidence: ["LSApplicationCategoryType = \(value)"],
                    fix: "Use one of the public.app-category values from Apple's documentation, for example public.app-category.productivity."
                ))
            } else {
                findings.append(finding(
                    "Mac app category set",
                    message: "'\(target.name)' uses the category \(value).",
                    severity: .pass,
                    confidence: .high,
                    file: file,
                    target: target,
                    evidence: ["LSApplicationCategoryType = \(value)"]
                ))
            }
        }

        if !apps.isEmpty {
            findings.append(finding(
                "App Store Connect metadata needs review",
                message: "Some submission requirements live only in App Store Connect and cannot be checked from the project.",
                severity: .manualReview,
                confidence: .high,
                evidence: [
                    "Privacy policy URL in App Store Connect, and a link inside the app (Guideline 5.1.1(i))",
                    "App Privacy details match what the app and its SDKs collect",
                    "Screenshots, description, and URLs are final, with no placeholder content (Guideline 2.1)",
                    "Demo account or demo mode in the review notes if the app has a login (Guideline 2.1)",
                ],
                fix: "Check each item in App Store Connect before submitting for review.",
                documentation: "https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage"
            ))
        }
        return findings
    }
}
