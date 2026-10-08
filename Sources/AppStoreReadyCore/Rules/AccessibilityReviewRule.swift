import Foundation

/// ASR010: a reminder that accessibility cannot be verified statically.
public struct AccessibilityReviewRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR010",
        title: "Accessibility",
        description: "Accessibility depends on runtime behavior (VoiceOver labels, Dynamic Type, contrast) that a static scan cannot evaluate. This rule always produces an informational reminder.",
        category: .accessibility,
        documentationURL: URL(string: "https://developer.apple.com/accessibility/")
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        guard context.targets.contains(where: { $0.productType.isApplication }) else { return [] }
        return [finding(
            "Accessibility audit requires runtime testing",
            message: "Run the app with VoiceOver and larger Dynamic Type sizes, and use Accessibility Inspector's audit to check labels, contrast, and hit targets.",
            severity: .info,
            confidence: .high,
            fix: "Xcode › Open Developer Tool › Accessibility Inspector, then run an audit on each screen."
        )]
    }
}
