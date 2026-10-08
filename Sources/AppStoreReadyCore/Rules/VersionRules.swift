import Foundation

/// ASR003: CFBundleShortVersionString must be present and well formed.
public struct VersionRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR003",
        title: "Version number",
        description: "Checks that CFBundleShortVersionString (MARKETING_VERSION) is set and consists of period-separated integers, as Apple's documentation describes.",
        category: .versioning,
        documentationURL: URL(string: "https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring")
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.compactMap { target in
            evaluateVersionKey(
                rule: self,
                key: "CFBundleShortVersionString",
                setting: "MARKETING_VERSION",
                label: "version",
                maxComponents: 3,
                target: target,
                context: context
            )
        }
    }
}

/// ASR004: CFBundleVersion (the build number) must be present and well formed.
public struct BuildNumberRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR004",
        title: "Build number",
        description: "Checks that CFBundleVersion (CURRENT_PROJECT_VERSION) is set and consists of period-separated integers. Apple documents this key as required by the App Store.",
        category: .versioning,
        documentationURL: URL(string: "https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion")
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.compactMap { target in
            evaluateVersionKey(
                rule: self,
                key: "CFBundleVersion",
                setting: "CURRENT_PROJECT_VERSION",
                label: "build number",
                maxComponents: nil,
                target: target,
                context: context
            )
        }
    }
}

private let numericVersion = TextPattern(#"^[0-9]+(\.[0-9]+)*$"#)

private func evaluateVersionKey(
    rule: some Rule,
    key: String,
    setting: String,
    label: String,
    maxComponents: Int?,
    target: ResolvedTarget,
    context: ScanContext
) -> Finding? {
    // Targets without an Info.plist are reported by the bundle identifier rule.
    guard let info = target.infoPlist, !info.isUnreadable else { return nil }
    let file = context.infoPlistLocation(for: target, key: key)
    let fix = "Set \(setting) for the \(target.configurationName) configuration (target › General › Identity) and reference it from Info.plist as $(\(setting))."
    let missingTitle = label == "version" ? "Missing version number" : "Missing build number"

    guard let raw = info.rawString(key), !raw.trimmingCharacters(in: .whitespaces).isEmpty else {
        return rule.finding(
            missingTitle,
            message: "The Info.plist of '\(target.name)' has no \(key).",
            severity: .error,
            confidence: .high,
            file: file,
            target: target,
            fix: fix
        )
    }

    let value = info.string(key)?.trimmingCharacters(in: .whitespaces) ?? ""
    if value.isEmpty {
        var evidence = ["\(key) = \(raw)"]
        if let note = describeUndefined(raw, settings: target.buildSettings) {
            evidence.append(note + " in the \(target.configurationName) configuration")
        }
        return rule.finding(
            missingTitle,
            message: "\(key) of '\(target.name)' resolves to an empty value.",
            severity: .error,
            confidence: .high,
            file: file,
            target: target,
            evidence: evidence,
            fix: fix
        )
    }

    let components = value.split(separator: ".", omittingEmptySubsequences: false).count
    if !numericVersion.matches(value) || (maxComponents.map { components > $0 } ?? false) {
        let expected = maxComponents.map { "one to \($0) period-separated integers" } ?? "period-separated integers"
        return rule.finding(
            "Invalid \(label)",
            message: "\(key) '\(value)' of '\(target.name)' is not \(expected), for example 1.2.3.",
            severity: .error,
            confidence: .high,
            file: file,
            target: target,
            evidence: ["\(key) = \(value)"],
            fix: "Use only digits and periods, such as 1.4.0, in \(setting)."
        )
    }

    if target.productType == .appExtension, let app = containingApp(of: target, context: context),
       let appValue = app.infoPlist?.string(key), !appValue.isEmpty, appValue != value {
        return rule.finding(
            "Extension \(label) differs from the app",
            message: "App extension '\(target.name)' has \(key) '\(value)' but the app '\(app.name)' has '\(appValue)'. App Store Connect expects extensions to match their containing app.",
            severity: .warning,
            confidence: .medium,
            file: file,
            target: target,
            evidence: ["\(app.name): \(appValue)", "\(target.name): \(value)"],
            fix: "Use the same \(setting) for the extension as for the app, for example by defining it once at the project level."
        )
    }

    return rule.finding(
        label == "version" ? "Version number configured" : "Build number configured",
        message: "'\(target.name)' has \(key) '\(value)'.",
        severity: .pass,
        confidence: .high,
        file: file,
        target: target,
        evidence: ["\(key) = \(value)"]
    )
}
