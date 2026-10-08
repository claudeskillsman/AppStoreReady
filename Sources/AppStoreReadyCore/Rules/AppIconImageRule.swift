import Foundation

/// ASR021: pixel dimensions and transparency of app icon images.
public struct AppIconImageRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR021",
        title: "App icon images",
        description: "Reads the PNG header of each image in an app's icon set and checks that its pixel size matches the size and scale declared in Contents.json, and that the 1024x1024 App Store icon has no alpha channel.",
        rationale: "Apple documents exact pixel sizes for app icons, such as a single 1024×1024 pixel image for iOS. An image whose pixel size does not match its slot is not the icon the system expects for that slot.",
        category: .assets,
        references: [
            Reference("Configuring your app icon", "https://developer.apple.com/documentation/xcode/configuring-your-app-icon"),
            Reference("Human Interface Guidelines: App icons", "https://developer.apple.com/design/human-interface-guidelines/app-icons"),
        ]
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.filter(\.productType.isApplication).compactMap { target in
            guard let iconSet = context.appIconSet(for: target), let images = iconSet.images else { return nil }
            let file = iconSet.relativePath + "/Contents.json"
            var mismatched: [String] = []
            var transparentLarge: [String] = []
            var notPNG: [String] = []
            for image in images where image.fileExists {
                guard let filename = image.filename else { continue }
                guard let png = image.png else {
                    notPNG.append(filename)
                    continue
                }
                if let expected = expectedPixels(size: image.size, scale: image.scale), expected != (png.width, png.height) {
                    mismatched.append("\(filename) is \(png.width)x\(png.height) pixels; Contents.json expects \(expected.0)x\(expected.1)")
                }
                // Dark and tinted variants are meant to be transparent.
                if png.hasAlpha, image.appearance == nil, png.width >= 1024 || image.idiom == "ios-marketing" {
                    transparentLarge.append(filename)
                }
            }

            if !mismatched.isEmpty {
                return finding(
                    "App icon image has the wrong size",
                    message: "Some images in '\(iconSet.relativePath)' do not match the size declared for their slot.",
                    severity: .warning,
                    confidence: .high,
                    classification: .verifiedIssue,
                    file: file,
                    target: target,
                    evidence: mismatched,
                    fix: "Export each icon at the exact pixel size of its slot (size × scale)."
                )
            }
            if !transparentLarge.isEmpty {
                return finding(
                    "Large app icon has an alpha channel",
                    message: "The default 1024-pixel icon in '\(iconSet.relativePath)' has an alpha channel. Apple's Human Interface Guidelines ask for a full-bleed, opaque background layer; transparency is intended only for the dark variant.",
                    severity: .info,
                    confidence: .medium,
                    classification: .bestPractice,
                    file: file,
                    target: target,
                    evidence: transparentLarge.map { "\($0) has an alpha channel" },
                    fix: "Export the 1024x1024 icon as a PNG without an alpha channel (flatten it onto an opaque background)."
                )
            }
            if !notPNG.isEmpty {
                return finding(
                    "App icon images could not be inspected",
                    message: "Some icon images are not PNG files, so their size and transparency were not checked.",
                    severity: .info,
                    confidence: .high,
                    classification: .manualReview,
                    file: file,
                    target: target,
                    evidence: notPNG,
                    fix: "Use PNG images for app icons, or check these images manually."
                )
            }
            return finding(
                "App icon images match their slots",
                message: "Images in '\(iconSet.relativePath)' have the declared pixel sizes and the App Store icon is opaque.",
                severity: .pass,
                confidence: .high,
                file: file,
                target: target
            )
        }
    }

    /// `size` is like "1024x1024" or "83.5x83.5"; `scale` like "2x".
    func expectedPixels(size: String?, scale: String?) -> (Int, Int)? {
        guard let size else { return nil }
        let parts = size.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        let factor = scale.flatMap { Double($0.replacingOccurrences(of: "x", with: "")) } ?? 1
        return (Int((parts[0] * factor).rounded()), Int((parts[1] * factor).rounded()))
    }
}
