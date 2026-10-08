import Foundation

/// ASR007: required reason APIs must be declared in a privacy manifest.
///
/// This rule only reports a failure when the requirement demonstrably
/// applies: source code in the target uses an API from one of Apple's
/// required reason categories. A missing manifest on its own is a
/// manual review item, because the need for one can come from
/// third-party SDKs or data collection that a static scan cannot see.
public struct PrivacyManifestRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR007",
        title: "Privacy manifest",
        description: "Detects use of required reason APIs (file timestamps, system boot time, disk space, active keyboards, user defaults) and checks that a PrivacyInfo.xcprivacy in the target declares each category with at least one reason.",
        category: .privacy,
        documentationURL: URL(string: "https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api")
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.flatMap { evaluate($0, context: context) }
    }

    private func evaluate(_ target: ResolvedTarget, context: ScanContext) -> [Finding] {
        let (files, exactFiles) = context.codeFiles(for: target)
        var used: [(category: RequiredReasonCategory, file: SourceFile, line: Int)] = []
        for category in APIUsageCatalog.requiredReasonCategories {
            if let match = context.firstMatch(of: category.patterns, in: files) {
                used.append((category, match.file, match.line))
            }
        }

        let manifests: [PrivacyManifest]
        let orphans: [PrivacyManifest]
        if target.target.hasKnownMembership {
            manifests = context.privacyManifests.filter { target.target.contains(path: $0.path) }
            orphans = context.privacyManifests.filter { !target.target.contains(path: $0.path) }
        } else {
            manifests = context.privacyManifests
            orphans = []
        }
        // Malformed manifests are reported by ASR001; do not guess about their contents.
        if manifests.contains(where: { $0.contents == nil }) { return [] }

        let usageEvidence = used.map { "\($0.file.relativePath):\($0.line) uses \($0.category.name) (\($0.category.identifier))" }
        let docURL = metadata.documentationURL

        if manifests.isEmpty {
            if used.isEmpty {
                guard target.productType.isApplication else { return [] }
                return [finding(
                    "Privacy manifest needs review",
                    message: "'\(target.name)' has no PrivacyInfo.xcprivacy. No required reason API usage was detected in its source, but a manifest can still be needed for data collection, tracking, or third-party SDKs.",
                    severity: .manualReview,
                    confidence: .low,
                    file: context.projectFile(for: target),
                    target: target,
                    fix: "Review the app's data collection and the SDKs it embeds. If any apply, add a privacy manifest (File › New › File › App Privacy)."
                )]
            }
            if let orphan = orphans.first {
                return [finding(
                    "Privacy manifest not included in target",
                    message: "'\(target.name)' uses required reason APIs. A privacy manifest exists at \(orphan.relativePath) but it is not a member of this target.",
                    severity: .error,
                    confidence: .medium,
                    file: orphan.relativePath,
                    target: target,
                    evidence: usageEvidence,
                    fix: "Add PrivacyInfo.xcprivacy to the target's Copy Bundle Resources phase (File Inspector › Target Membership)."
                )]
            }
            return [finding(
                "Missing privacy manifest",
                message: "'\(target.name)' uses required reason APIs but has no PrivacyInfo.xcprivacy. Apple requires apps that use these APIs to declare the reasons in a privacy manifest.",
                severity: exactFiles ? .error : .warning,
                confidence: exactFiles ? .medium : .low,
                file: used[0].file.relativePath,
                line: used[0].line,
                target: target,
                evidence: usageEvidence,
                fix: "Add a privacy manifest (File › New › File › App Privacy) to the target and declare each API category under NSPrivacyAccessedAPITypes with an approved reason."
            )]
        }

        var findings: [Finding] = []
        var declared: [String: [String]] = [:]
        for manifest in manifests {
            declared.merge(manifest.declaredAPICategories) { $0 + $1 }
        }
        let manifestFile = manifests[0].relativePath

        for usage in used {
            guard let reasons = declared[usage.category.identifier] else {
                findings.append(finding(
                    "Required reason API not declared",
                    message: "'\(target.name)' uses \(usage.category.name), but its privacy manifest does not declare \(usage.category.identifier).",
                    severity: exactFiles ? .error : .warning,
                    confidence: exactFiles ? .medium : .low,
                    file: manifestFile,
                    target: target,
                    evidence: ["\(usage.file.relativePath):\(usage.line) uses \(usage.category.name)"],
                    fix: "Add an NSPrivacyAccessedAPITypes entry with NSPrivacyAccessedAPIType = \(usage.category.identifier) and the reason code that matches your use. Reason codes: \(docURL?.absoluteString ?? "")"
                ))
                continue
            }
            if reasons.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).isEmpty {
                findings.append(finding(
                    "Required reason API declared without a reason",
                    message: "\(usage.category.identifier) is declared in the privacy manifest with no NSPrivacyAccessedAPITypeReasons.",
                    severity: .error,
                    confidence: .high,
                    file: manifestFile,
                    target: target,
                    evidence: ["\(usage.category.identifier): no reasons listed"],
                    fix: "Add the approved reason code (for example CA92.1 for user defaults accessed only by the app) to NSPrivacyAccessedAPITypeReasons."
                ))
            }
        }

        for manifest in manifests {
            let tracking = manifest.contents?["NSPrivacyTracking"]?.boolValue ?? false
            let domains = manifest.contents?["NSPrivacyTrackingDomains"]?.arrayValue ?? []
            if tracking && domains.isEmpty {
                findings.append(finding(
                    "Tracking enabled without tracking domains",
                    message: "NSPrivacyTracking is true but NSPrivacyTrackingDomains is empty. Apple's documentation says to list the tracking domains when NSPrivacyTracking is true.",
                    severity: .warning,
                    confidence: .high,
                    file: manifest.relativePath,
                    target: target,
                    fix: "List the internet domains the app connects to for tracking, or set NSPrivacyTracking to false if the app does not track."
                ))
            }
        }

        if findings.isEmpty {
            findings.append(finding(
                "Privacy manifest present",
                message: used.isEmpty
                    ? "'\(target.name)' includes a privacy manifest."
                    : "'\(target.name)' includes a privacy manifest that declares the required reason APIs detected in its source.",
                severity: .pass,
                confidence: .medium,
                file: manifestFile,
                target: target,
                evidence: used.map { "\($0.category.identifier) declared" }
            ))
        }
        return findings
    }
}
