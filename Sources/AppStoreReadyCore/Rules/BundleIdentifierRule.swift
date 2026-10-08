import Foundation

/// ASR002: every app and extension needs a valid bundle identifier.
public struct BundleIdentifierRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR002",
        title: "Bundle identifier",
        description: "Checks that each app and app extension has a CFBundleIdentifier that resolves to a non-empty value containing only the characters Apple documents as valid (A-Z, a-z, 0-9, hyphen, period).",
        category: .configuration,
        documentationURL: URL(string: "https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier")
    )

    private static let validCharacters = TextPattern(#"^[A-Za-z0-9.\-]+$"#)
    private static let placeholderMarkers = ["com.example", "com.yourcompany", "com.mycompany", "com.company.", "org.example"]

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.flatMap { evaluate($0, context: context) }
    }

    private func evaluate(_ target: ResolvedTarget, context: ScanContext) -> [Finding] {
        let fix = "Set PRODUCT_BUNDLE_IDENTIFIER for the \(target.configurationName) configuration (target › Signing & Capabilities › Bundle Identifier), and make sure Info.plist uses $(PRODUCT_BUNDLE_IDENTIFIER)."
        guard let info = target.infoPlist else {
            return [finding(
                "No Info.plist configured",
                message: "Target '\(target.name)' neither sets INFOPLIST_FILE nor GENERATE_INFOPLIST_FILE, so it has no Info.plist.",
                severity: .error,
                confidence: .high,
                file: context.projectFile(for: target),
                target: target,
                fix: "Set GENERATE_INFOPLIST_FILE = YES or point INFOPLIST_FILE at an Info.plist file."
            )]
        }

        if info.isUnreadable { return [] }
        let file = context.infoPlistLocation(for: target, key: "CFBundleIdentifier")
        guard let raw = info.rawString("CFBundleIdentifier"), !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
            return [finding(
                "Missing bundle identifier",
                message: "The Info.plist of '\(target.name)' has no CFBundleIdentifier.",
                severity: .error,
                confidence: .high,
                file: file,
                target: target,
                fix: fix
            )]
        }

        let value = info.string("CFBundleIdentifier")?.trimmingCharacters(in: .whitespaces) ?? ""
        if value.isEmpty {
            var evidence = ["CFBundleIdentifier = \(raw)"]
            if let note = describeUndefined(raw, settings: target.buildSettings) {
                evidence.append(note + " in the \(target.configurationName) configuration")
            }
            return [finding(
                "Missing bundle identifier",
                message: "CFBundleIdentifier of '\(target.name)' resolves to an empty value.",
                severity: .error,
                confidence: .high,
                file: file,
                target: target,
                evidence: evidence,
                fix: fix
            )]
        }

        if !Self.validCharacters.matches(value) {
            return [finding(
                "Invalid bundle identifier",
                message: "Bundle identifier '\(value)' contains characters other than A-Z, a-z, 0-9, hyphen, and period.",
                severity: .error,
                confidence: .high,
                file: file,
                target: target,
                evidence: ["CFBundleIdentifier = \(value)"],
                fix: "Use only alphanumeric characters, hyphens, and periods, for example com.company.app."
            )]
        }

        let lowered = value.lowercased()
        if Self.placeholderMarkers.contains(where: { lowered.hasPrefix($0) }) {
            return [finding(
                "Bundle identifier looks like a placeholder",
                message: "Bundle identifier '\(value)' looks like a template default. It must match the App ID registered for the app in App Store Connect.",
                severity: .warning,
                confidence: .medium,
                file: file,
                target: target,
                evidence: ["CFBundleIdentifier = \(value)"],
                fix: "Replace it with the reverse-DNS identifier you registered, for example com.yourdomain.appname."
            )]
        }

        if target.productType == .appExtension, let parent = containingApp(of: target, context: context),
           let parentID = parent.infoPlist?.string("CFBundleIdentifier"), !parentID.isEmpty,
           !value.hasPrefix(parentID + ".") {
            return [finding(
                "Extension bundle identifier is not prefixed by the app's",
                message: "App extension '\(target.name)' uses '\(value)', which does not start with the containing app's identifier '\(parentID).'.",
                severity: .warning,
                confidence: .medium,
                file: file,
                target: target,
                evidence: ["App: \(parentID)", "Extension: \(value)"],
                fix: "Use an identifier of the form \(parentID).<extension-name>."
            )]
        }

        return [finding(
            "Bundle identifier configured",
            message: "'\(target.name)' uses bundle identifier '\(value)'.",
            severity: .pass,
            confidence: .high,
            file: file,
            target: target,
            evidence: ["CFBundleIdentifier = \(value)"]
        )]
    }
}

/// The single application target in the same project, used as the presumed
/// container of an extension. Returns nil when that cannot be decided.
func containingApp(of target: ResolvedTarget, context: ScanContext) -> ResolvedTarget? {
    let apps = context.targets.filter {
        $0.project.url == target.project.url && $0.productType == .application
    }
    return apps.count == 1 ? apps[0] : nil
}
