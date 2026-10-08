import Foundation

/// ASR023: static hints about accessibility support. Never a compliance verdict.
public struct AccessibilityHintsRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR023",
        title: "Accessibility hints",
        description: "Looks for signs of accessibility support in app source code: accessibility labels and Dynamic Type support for custom font sizes. Findings are recommendations only; static analysis cannot verify accessibility.",
        rationale: "Missing labels make controls unusable with VoiceOver, and fixed font sizes ignore the reader's text size setting. These hints point to places worth testing; they do not measure compliance.",
        category: .accessibility,
        references: [
            Reference("Accessibility for UIKit", "https://developer.apple.com/documentation/uikit/accessibility-for-uikit"),
            Reference("Scaling fonts automatically", "https://developer.apple.com/documentation/uikit/scaling-fonts-automatically"),
            Reference("Human Interface Guidelines: Accessibility", "https://developer.apple.com/design/human-interface-guidelines/accessibility"),
        ]
    )

    static let ui = TextPattern(#"\bimport\s+(SwiftUI|UIKit|AppKit)\b|#import\s+<UIKit/"#)
    static let labels = TextPattern(#"accessibilityLabel|accessibilityHint|accessibilityValue|isAccessibilityElement|accessibilityElements|\.accessibilityElement\(|accessibilityRepresentation"#)
    static let fixedFonts = TextPattern(#"\.system\(size:|UIFont\.systemFont\(ofSize:|UIFont\(name:[^)]*size:|\.custom\([^)]*size:[^)]*\)(?!.*relativeTo)"#)
    static let dynamicType = TextPattern(#"UIFontMetrics|adjustsFontForContentSizeCategory|relativeTo:|@ScaledMetric|preferredFont\(forTextStyle"#)

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.filter(\.productType.isApplication).compactMap { target in
            let files = context.codeFiles(for: target).files.filter { !isTestPath($0.relativePath) }
            let uiFiles = files.filter { Self.ui.matches($0.contents) }
            guard !uiFiles.isEmpty else { return nil }
            var notes: [String] = []
            if !files.contains(where: { Self.labels.matches($0.contents) }) {
                notes.append("No accessibility labels, hints, or values found in \(uiFiles.count) UI source file(s).")
            }
            let usesFixed = context.firstMatch(of: [Self.fixedFonts], in: files)
            if let usesFixed, !files.contains(where: { Self.dynamicType.matches($0.contents) }) {
                notes.append("Fixed font sizes without Dynamic Type scaling, for example \(usesFixed.file.relativePath):\(usesFixed.line).")
            }
            guard !notes.isEmpty else {
                return finding(
                    "Accessibility APIs are used",
                    message: "'\(target.name)' uses accessibility labels and scales custom fonts. This does not verify accessibility; test with VoiceOver and Dynamic Type.",
                    severity: .pass,
                    confidence: .low,
                    target: target
                )
            }
            return finding(
                "Accessibility support may be incomplete",
                message: "Static hints suggest '\(target.name)' may not support VoiceOver or Dynamic Type everywhere. Standard controls are often accessible by default, so confirm by testing.",
                severity: .info,
                confidence: .low,
                classification: .bestPractice,
                target: target,
                evidence: notes,
                fix: "Add accessibilityLabel to images and icon-only buttons, and use text styles or UIFontMetrics / relativeTo: for custom fonts."
            )
        }
    }
}
