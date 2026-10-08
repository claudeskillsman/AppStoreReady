import Foundation

/// A check that inspects a scanned project and reports findings.
///
/// To add a rule:
/// 1. Create a type conforming to `Rule` with a new, unique `metadata.id`.
/// 2. Return findings from `evaluate(_:)` — use `finding(...)` so the
///    rule's identifier, category, and documentation link are filled in.
/// 3. Register it in `RuleRegistry.builtIn` and add tests with fixtures.
///
/// Rules must be pure: read from the `ScanContext` only, never touch the
/// network, never run project code, and never put secret values in findings.
public protocol Rule: Sendable {
    var metadata: RuleMetadata { get }
    func evaluate(_ context: ScanContext) -> [Finding]
}

extension Rule {
    func finding(
        _ title: String,
        message: String,
        severity: Severity,
        confidence: Confidence,
        classification: Classification? = nil,
        file: String? = nil,
        line: Int? = nil,
        target: ResolvedTarget? = nil,
        evidence: [String] = [],
        fix: String? = nil,
        documentation: String? = nil
    ) -> Finding {
        Finding(
            ruleID: metadata.id,
            title: title,
            message: message,
            severity: severity,
            classification: classification,
            category: metadata.category,
            confidence: confidence,
            file: file,
            line: line,
            target: target?.name,
            configuration: target?.configurationName,
            evidence: evidence,
            whyItMatters: severity == .pass ? nil : metadata.rationale,
            suggestedFix: severity == .pass ? nil : fix,
            documentationURL: documentation.flatMap(URL.init(string:)) ?? metadata.documentationURL
        )
    }
}

/// All rules that ship with AppStoreReady, in report order.
public enum RuleRegistry {
    /// Metadata for findings the engine produces about suppressions themselves.
    public static let suppressionsMetadata = RuleMetadata(
        id: "ASR000",
        title: "Suppressions",
        description: "Reports suppressions in .appstoreready.yml that have expired, that match nothing, or that hide an ERROR-level security finding.",
        rationale: "Suppressions hide findings from the report and the exit code. Expired or stale entries, and hidden security problems, need to stay visible so they are revisited.",
        category: .manualReview,
        references: [
            Reference("AppStoreReady suppressions", "https://github.com/charliegkoch-design/AppStoreReady#suppressing-findings"),
        ]
    )

    /// Metadata for every rule, including ASR000.
    public static var allMetadata: [RuleMetadata] {
        [suppressionsMetadata] + builtIn.map(\.metadata)
    }

    public static var allRuleIDs: Set<String> {
        Set(allMetadata.map(\.id))
    }

    public static let builtIn: [any Rule] = [
        ProjectFilesRule(),
        BundleIdentifierRule(),
        VersionRule(),
        BuildNumberRule(),
        AppIconRule(),
        PrivacyUsageDescriptionRule(),
        PrivacyManifestRule(),
        HardcodedSecretRule(),
        DebugConfigurationRule(),
        AccessibilityReviewRule(),
        LaunchScreenRule(),
        DeploymentTargetRule(),
        EncryptionExportRule(),
        AppTransportSecurityRule(),
        InsecureURLRule(),
        CredentialFilesRule(),
        SigningConfigurationRule(),
        EntitlementsRule(),
        BackgroundModesRule(),
        ThirdPartySDKRule(),
        AppIconImageRule(),
        ReleaseBuildSettingsRule(),
        AccessibilityHintsRule(),
        AppStoreMetadataRule(),
        GuidelineReviewRule(),
    ]
}

extension ScanContext {
    /// The file a target's Info.plist value comes from: the Info.plist file
    /// when the key is defined there (or when there is no generated plist),
    /// otherwise the project file that holds the build settings.
    func infoPlistLocation(for target: ResolvedTarget, key: String) -> String {
        if let info = target.infoPlist, let url = info.url, info.keysFromFile.contains(key) || !info.isGenerated {
            return relativePath(url)
        }
        return projectFile(for: target)
    }

    func projectFile(for target: ResolvedTarget) -> String {
        relativePath(target.project.url.appendingPathComponent("project.pbxproj"))
    }

    /// Finds the first line in `files` matching any pattern, ignoring comment lines.
    func firstMatch(of patterns: [TextPattern], in files: [SourceFile]) -> (file: SourceFile, line: Int)? {
        for file in files {
            for (index, line) in file.lines.enumerated() where !SourceText.isCommentLine(line) {
                let text = String(line)
                if patterns.contains(where: { $0.matches(text) }) {
                    return (file, index + 1)
                }
            }
        }
        return nil
    }
}

/// Describes where a configuration value came from, for evidence lines.
func describeUndefined(_ raw: String, settings: BuildSettings) -> String? {
    let undefined = settings.expandTracking(raw).undefined
    guard !undefined.isEmpty else { return nil }
    return "references \(undefined.map { "$(\($0))" }.joined(separator: ", ")), which is not set"
}

extension ScanContext {
    /// The app icon set a target uses, preferring one that is a member of the target.
    func appIconSet(for target: ResolvedTarget) -> AppIconSet? {
        guard let name = target.buildSettings.value("ASSETCATALOG_COMPILER_APPICON_NAME")?.trimmingCharacters(in: .whitespaces), !name.isEmpty else {
            return nil
        }
        let named = appIconSets.filter { $0.name == name }
        let inTarget = target.target.hasKnownMembership ? named.filter { target.target.contains(path: $0.path) } : named
        return inTarget.first ?? named.first
    }

    /// Text files (code and property lists) that belong to a target, or all
    /// of them when membership is unknown.
    func memberFiles(for target: ResolvedTarget, where include: (SourceFile) -> Bool) -> [SourceFile] {
        let candidates = files.filter(include)
        guard target.target.hasKnownMembership else { return candidates }
        return candidates.filter { target.target.contains(path: $0.path) }
    }
}

/// True for paths inside test, fixture, or mock folders.
func isTestPath(_ relativePath: String) -> Bool {
    relativePath.split(separator: "/").dropLast().contains { component in
        component.hasSuffix("Tests") || component == "Fixtures" || component == "Mocks" || component == "Test"
    }
}
