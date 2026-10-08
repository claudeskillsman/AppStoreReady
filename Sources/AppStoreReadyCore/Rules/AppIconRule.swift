import Foundation

/// ASR005: apps need an app icon configured in an asset catalog or Info.plist.
public struct AppIconRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR005",
        title: "App icon",
        description: "Checks that each application target names an app icon set (ASSETCATALOG_COMPILER_APPICON_NAME) that exists in an asset catalog and contains images, including a 1024x1024 App Store icon.",
        rationale: "App Store Connect requires an app icon, and the 1024x1024 image is used for the App Store listing. Builds without one are rejected during upload processing.",
        category: .assets,
        references: [
            Reference("Configuring your app icon", "https://developer.apple.com/documentation/xcode/configuring-your-app-icon"),
        ]
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.filter(\.productType.isApplication).compactMap { evaluate($0, context: context) }
    }

    private func evaluate(_ target: ResolvedTarget, context: ScanContext) -> Finding? {
        let projectFile = context.projectFile(for: target)
        let iconName = target.buildSettings.value("ASSETCATALOG_COMPILER_APPICON_NAME")?.trimmingCharacters(in: .whitespaces) ?? ""
        let plistIconKeys = ["CFBundleIcons", "CFBundleIconFile", "CFBundleIconFiles", "CFBundleIconName"]
            .filter { target.infoPlist?.resolved[$0] != nil }

        guard !iconName.isEmpty else {
            if !plistIconKeys.isEmpty {
                return finding(
                    "App icon configured in Info.plist",
                    message: "'\(target.name)' declares icons with Info.plist keys instead of an asset catalog setting.",
                    severity: .pass,
                    confidence: .medium,
                    file: context.infoPlistLocation(for: target, key: plistIconKeys[0]),
                    target: target,
                    evidence: plistIconKeys.map { "Info.plist key \($0) present" }
                )
            }
            return finding(
                "Missing app icon configuration",
                message: "'\(target.name)' does not set ASSETCATALOG_COMPILER_APPICON_NAME and declares no icon in Info.plist.",
                severity: .error,
                confidence: .medium,
                file: projectFile,
                target: target,
                evidence: ["ASSETCATALOG_COMPILER_APPICON_NAME is not set in \(target.configurationName)"],
                fix: "Add an App Icon to an asset catalog and set the target's App Icon (ASSETCATALOG_COMPILER_APPICON_NAME), usually to AppIcon."
            )
        }

        let named = context.appIconSets.filter { $0.name == iconName }
        let inTarget = target.target.hasKnownMembership ? named.filter { target.target.contains(path: $0.path) } : named
        guard let iconSet = inTarget.first ?? named.first else {
            return finding(
                "App icon set not found",
                message: "'\(target.name)' uses app icon '\(iconName)', but no '\(iconName).appiconset' was found in the project's asset catalogs.",
                severity: .error,
                confidence: .medium,
                file: projectFile,
                target: target,
                evidence: ["ASSETCATALOG_COMPILER_APPICON_NAME = \(iconName)"],
                fix: "Create the '\(iconName)' app icon set in the target's asset catalog, or change the setting to the name of an existing set."
            )
        }

        let contentsFile = iconSet.relativePath + "/Contents.json"
        guard let images = iconSet.images else {
            // A malformed Contents.json is already reported by ASR001.
            if context.parseIssues.contains(where: { $0.relativePath == contentsFile }) { return nil }
            return finding(
                "App icon set has no Contents.json",
                message: "'\(iconSet.relativePath)' has no Contents.json, so Xcode cannot read the icon set.",
                severity: .warning,
                confidence: .high,
                file: contentsFile,
                target: target,
                fix: "Recreate the app icon set in Xcode's asset catalog editor."
            )
        }

        let present = images.filter { $0.filename != nil && $0.fileExists }
        let missingFiles = images.compactMap { $0.filename != nil && !$0.fileExists ? $0.filename : nil }
        if present.isEmpty {
            return finding(
                "App icon set contains no images",
                message: "'\(iconSet.relativePath)' exists but no icon image is assigned to it.",
                severity: .error,
                confidence: .high,
                file: contentsFile,
                target: target,
                evidence: missingFiles.map { "Missing file: \($0)" },
                fix: "Drag a 1024x1024 PNG into the App Icon set in Xcode."
            )
        }
        if !missingFiles.isEmpty {
            return finding(
                "App icon set references missing files",
                message: "'\(iconSet.relativePath)' lists image files that do not exist.",
                severity: .warning,
                confidence: .high,
                file: contentsFile,
                target: target,
                evidence: missingFiles.map { "Missing file: \($0)" },
                fix: "Add the missing images or remove the stale entries in Xcode."
            )
        }
        let hasLargeIcon = present.contains { $0.size == "1024x1024" || $0.size == "512x512" }
        if !hasLargeIcon {
            return finding(
                "No 1024x1024 App Store icon",
                message: "'\(iconSet.relativePath)' has no 1024x1024 image. App Store Connect uses the large icon for the App Store listing.",
                severity: .warning,
                confidence: .medium,
                file: contentsFile,
                target: target,
                evidence: ["Sizes present: \(Set(present.compactMap(\.size)).sorted().joined(separator: ", "))"],
                fix: "Add a 1024x1024 PNG without transparency to the icon set."
            )
        }
        return finding(
            "App icon configuration detected",
            message: "'\(target.name)' uses app icon set '\(iconName)' with \(present.count) image(s).",
            severity: .pass,
            confidence: .high,
            file: contentsFile,
            target: target,
            evidence: ["ASSETCATALOG_COMPILER_APPICON_NAME = \(iconName)"]
        )
    }
}
