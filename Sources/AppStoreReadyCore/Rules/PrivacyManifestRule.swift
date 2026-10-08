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
        description: "Detects use of required reason APIs (file timestamps, system boot time, disk space, active keyboards, user defaults) and checks that a PrivacyInfo.xcprivacy in the target declares each category with an approved reason. Also validates the manifest's reason codes, collected data entries, and tracking settings against Apple's documented values.",
        rationale: "Apple's documentation states that, starting May 1, 2024, apps that don't describe their use of required reason API in their privacy manifest aren't accepted by App Store Connect. Xcode also can't build a correct privacy report from values Apple does not document.",
        category: .privacy,
        references: [
            Reference("Describing use of required reason API", "https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api"),
            Reference("Privacy manifest files", "https://developer.apple.com/documentation/bundleresources/privacy-manifest-files"),
            Reference("NSPrivacyAccessedAPIType", "https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype"),
            Reference("Describing data use in privacy manifests", "https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests"),
            Reference("NSPrivacyTracking", "https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacytracking"),
        ]
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.flatMap { evaluate($0, context: context) }
    }

    private func evaluate(_ target: ResolvedTarget, context: ScanContext) -> [Finding] {
        let (files, exactFiles) = context.codeFiles(for: target)
        var used: [(category: RequiredReasonCategory, file: SourceFile, line: Int)] = []
        // Apple lists required reasons for iOS, iPadOS, tvOS, visionOS, and watchOS; not macOS.
        let requiredReasonsApply = !target.sdk.hasPrefix("macosx")
        for category in APIUsageCatalog.requiredReasonCategories where requiredReasonsApply {
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
            findings += validate(manifest, target: target)
        }

        if let trackingUse = context.firstMatch(of: APIUsageCatalog.trackingPatterns, in: files),
           !manifests.contains(where: { $0.contents?["NSPrivacyTracking"]?.boolValue == true }) {
            findings.append(finding(
                "Tracking APIs used while the manifest declares no tracking",
                message: "'\(target.name)' uses App Tracking Transparency or the advertising identifier, but no privacy manifest in the target sets NSPrivacyTracking to true. Whether the app tracks, as defined by App Tracking Transparency, cannot be determined from code.",
                severity: .manualReview,
                confidence: .medium,
                file: trackingUse.file.relativePath,
                line: trackingUse.line,
                target: target,
                evidence: ["\(trackingUse.file.relativePath):\(trackingUse.line) uses tracking APIs"],
                fix: "If the app or its SDKs use data for tracking, set NSPrivacyTracking to true and list NSPrivacyTrackingDomains. Make sure the App Privacy details in App Store Connect match."
            ))
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

    /// Checks a manifest's values against the keys and values Apple documents.
    func validate(_ manifest: PrivacyManifest, target: ResolvedTarget) -> [Finding] {
        guard let contents = manifest.contents else { return [] }
        var findings: [Finding] = []
        let file = manifest.relativePath
        let categories = Dictionary(uniqueKeysWithValues: APIUsageCatalog.requiredReasonCategories.map { ($0.identifier, $0) })

        // NSPrivacyAccessedAPITypes
        var invalidAPI: [String] = []
        var sdkOnly: [String] = []
        for (index, entry) in (contents["NSPrivacyAccessedAPITypes"]?.arrayValue ?? []).enumerated() {
            guard let type = entry["NSPrivacyAccessedAPIType"]?.stringValue else {
                invalidAPI.append("NSPrivacyAccessedAPITypes[\(index)] has no NSPrivacyAccessedAPIType")
                continue
            }
            guard let category = categories[type] else {
                invalidAPI.append("NSPrivacyAccessedAPITypes[\(index)]: '\(type)' is not a documented API category")
                continue
            }
            for reason in entry["NSPrivacyAccessedAPITypeReasons"]?.arrayValue?.compactMap(\.stringValue) ?? [] {
                let code = reason.trimmingCharacters(in: .whitespaces)
                if code.isEmpty { continue }
                if !category.reasons.contains(code) {
                    invalidAPI.append("\(type): '\(code)' is not an approved reason for this category")
                } else if category.sdkOnlyReasons.contains(code), target.productType.isDistributableBundle {
                    sdkOnly.append("\(type): \(code)")
                }
            }
        }
        if !invalidAPI.isEmpty {
            findings.append(finding(
                "Invalid required reason declaration",
                message: "The privacy manifest for '\(target.name)' declares API categories or reason codes that Apple does not document.",
                severity: .error,
                confidence: .high,
                classification: .verifiedIssue,
                file: file,
                target: target,
                evidence: invalidAPI,
                fix: "Use only the NSPrivacyAccessedAPIType values and reason codes listed in Apple's documentation, and pick the reason that matches how the app uses the API."
            ))
        }
        if !sdkOnly.isEmpty {
            findings.append(finding(
                "SDK-only reason used in an app manifest",
                message: "The privacy manifest for '\(target.name)' uses a reason code that Apple reserves for third-party SDKs that wrap the API.",
                severity: .warning,
                confidence: .medium,
                classification: .potentialIssue,
                file: file,
                target: target,
                evidence: sdkOnly,
                fix: "Unless this target is itself a third-party SDK, choose the reason that describes the app's own use of the API."
            ))
        }

        // NSPrivacyCollectedDataTypes
        let requiredKeys = ["NSPrivacyCollectedDataType", "NSPrivacyCollectedDataTypeLinked", "NSPrivacyCollectedDataTypeTracking", "NSPrivacyCollectedDataTypePurposes"]
        var missingKeys: [String] = []
        var unknownValues: [String] = []
        for (index, entry) in (contents["NSPrivacyCollectedDataTypes"]?.arrayValue ?? []).enumerated() {
            let dictionary = entry.dictionaryValue ?? [:]
            let missing = requiredKeys.filter { dictionary[$0] == nil }
            if !missing.isEmpty {
                missingKeys.append("NSPrivacyCollectedDataTypes[\(index)] is missing \(missing.joined(separator: ", "))")
            }
            if let type = dictionary["NSPrivacyCollectedDataType"]?.stringValue, !APIUsageCatalog.collectedDataTypes.contains(type) {
                unknownValues.append("NSPrivacyCollectedDataTypes[\(index)]: data type '\(type)' is not a documented value")
            }
            for purpose in dictionary["NSPrivacyCollectedDataTypePurposes"]?.arrayValue?.compactMap(\.stringValue) ?? []
            where !APIUsageCatalog.collectedDataPurposes.contains(purpose) {
                unknownValues.append("NSPrivacyCollectedDataTypes[\(index)]: purpose '\(purpose)' is not a documented value")
            }
        }
        if !missingKeys.isEmpty {
            findings.append(finding(
                "Incomplete collected data entry",
                message: "Apple's documentation says each NSPrivacyCollectedDataTypes entry needs the data type, whether it is linked to the user, whether it is used for tracking, and its purposes.",
                severity: .error,
                confidence: .high,
                classification: .verifiedIssue,
                file: file,
                target: target,
                evidence: missingKeys,
                fix: "Add the missing keys to each collected data dictionary."
            ))
        }
        if !unknownValues.isEmpty {
            findings.append(finding(
                "Undocumented collected data value",
                message: "Apple's documentation says Xcode won't generate a privacy report correctly if you define your own collected data types or purposes.",
                severity: .warning,
                confidence: .high,
                classification: .verifiedIssue,
                file: file,
                target: target,
                evidence: unknownValues,
                fix: "Use the data type and purpose values listed in Apple's documentation (note the spelling NSPrivacyCollectedDataTypePhotosorVideos)."
            ))
        }

        // NSPrivacyTracking / NSPrivacyTrackingDomains
        let tracking = contents["NSPrivacyTracking"]?.boolValue ?? false
        let domains = contents["NSPrivacyTrackingDomains"]?.arrayValue ?? []
        if tracking && domains.isEmpty {
            findings.append(finding(
                "Tracking enabled without tracking domains",
                message: "NSPrivacyTracking is true but NSPrivacyTrackingDomains is empty. Apple's documentation says that when NSPrivacyTracking is true you need to provide the list of tracking domains.",
                severity: .warning,
                confidence: .high,
                classification: .verifiedIssue,
                file: file,
                target: target,
                fix: "List the internet domains the app connects to for tracking, or set NSPrivacyTracking to false if the app does not track."
            ))
        } else if !tracking && !domains.isEmpty {
            findings.append(finding(
                "Tracking domains listed while tracking is off",
                message: "NSPrivacyTrackingDomains lists \(domains.count) domain(s) but NSPrivacyTracking is not true. Apple's documentation says to set NSPrivacyTracking to true to provide tracking domains.",
                severity: .warning,
                confidence: .high,
                classification: .verifiedIssue,
                file: file,
                target: target,
                evidence: domains.compactMap(\.stringValue).prefix(10).map { "NSPrivacyTrackingDomains: \($0)" },
                fix: "Set NSPrivacyTracking to true if the app tracks, or remove NSPrivacyTrackingDomains."
            ))
        }
        return findings
    }
}
