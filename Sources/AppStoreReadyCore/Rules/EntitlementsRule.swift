import Foundation

/// ASR018: values in a target's entitlements file.
public struct EntitlementsRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR018",
        title: "Entitlements",
        description: "Validates entitlement values against Apple's documented formats: associated domains, app group identifiers, and aps-environment. Checks that HealthKit has its usage descriptions, that Mac apps enable the App Sandbox, and flags get-task-allow in the archived entitlements.",
        rationale: "Entitlements are checked against the provisioning profile when the app is signed and uploaded, and malformed values do not work at runtime. Apple documents a fixed format for each of these entitlements, and states that the App Sandbox is required for apps submitted to the Mac App Store.",
        category: .signing,
        references: [
            Reference("Associated Domains Entitlement", "https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.associated-domains"),
            Reference("App Groups Entitlement", "https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups"),
            Reference("APS Environment Entitlement", "https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment"),
            Reference("HealthKit Entitlement", "https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.healthkit"),
            Reference("Configuring the macOS App Sandbox", "https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox"),
            Reference("Resolving common notarization issues", "https://developer.apple.com/documentation/security/resolving-common-notarization-issues"),
        ]
    )

    static let associatedDomain = TextPattern(#"^(applinks|webcredentials|activitycontinuation|appclips):(\*\.)?[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9\-]*[A-Za-z0-9])?)+(:[0-9]+)?(\?mode=(developer|managed|developer\+managed))?$"#)
    static let macAppGroup = TextPattern(#"^[A-Z0-9]{10}\.[^\s]+$"#)
    static let healthAuthorization = [TextPattern(#"requestAuthorization\s*\(\s*toShare|requestAuthorizationToShareTypes"#)]

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.flatMap { evaluate($0, context: context) }
    }

    private func evaluate(_ target: ResolvedTarget, context: ScanContext) -> [Finding] {
        let isMac = target.sdk.hasPrefix("macosx")
        var findings: [Finding] = []

        if isMac, target.productType == .application {
            let sandboxed = target.entitlements?["com.apple.security.app-sandbox"]?.boolValue == true
                || target.buildSettings.value("ENABLE_APP_SANDBOX")?.uppercased() == "YES"
            if !sandboxed, target.entitlements?.contents != nil || target.entitlements == nil {
                findings.append(finding(
                    "App Sandbox is not enabled",
                    message: "'\(target.name)' is a macOS app without com.apple.security.app-sandbox in its entitlements. Apple's documentation states that the App Sandbox is an App Store requirement for any app submitted to the Mac App Store.",
                    severity: .error,
                    confidence: .high,
                    classification: .verifiedIssue,
                    file: target.entitlements.map { context.relativePath($0.url) } ?? context.projectFile(for: target),
                    target: target,
                    evidence: [target.entitlements == nil ? "CODE_SIGN_ENTITLEMENTS is not set" : "com.apple.security.app-sandbox is not true"],
                    fix: "Add the App Sandbox capability in Signing & Capabilities. If the app is distributed outside the Mac App Store, suppress this rule.",
                    documentation: "https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox"
                ))
            }
        }

        guard let entitlements = target.entitlements, entitlements.contents != nil else { return findings }
        let file = context.relativePath(entitlements.url)
        var invalid: [String] = []

        for value in entitlements["com.apple.developer.associated-domains"]?.arrayValue?.compactMap(\.stringValue) ?? [] where !value.contains("$(") {
            if !Self.associatedDomain.matches(value) {
                invalid.append("com.apple.developer.associated-domains: '\(value)' is not <service>:<domain> with a service of applinks, webcredentials, activitycontinuation, or appclips")
            }
        }
        for value in entitlements["com.apple.security.application-groups"]?.arrayValue?.compactMap(\.stringValue) ?? [] where !value.contains("$(") {
            let valid = value.hasPrefix("group.") && value.count > 6 || (isMac && Self.macAppGroup.matches(value))
            if !valid {
                invalid.append("com.apple.security.application-groups: '\(value)' should be group.<name>\(isMac ? " or <team ID>.<name>" : "")")
            }
        }
        if let aps = entitlements["aps-environment"]?.stringValue, !aps.contains("$("), aps != "development", aps != "production" {
            invalid.append("aps-environment: '\(aps)' must be development or production")
        }
        if !invalid.isEmpty {
            findings.append(finding(
                "Invalid entitlement value",
                message: "'\(target.name)' has entitlement values that do not match the format Apple documents.",
                severity: .error,
                confidence: .high,
                classification: .verifiedIssue,
                file: file,
                target: target,
                evidence: invalid,
                fix: "Correct the values in Signing & Capabilities so they follow the documented format."
            ))
        }

        if entitlements["com.apple.developer.healthkit"]?.boolValue == true, let info = target.infoPlist, !info.isUnreadable {
            let missing = ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"].filter { info.resolved[$0] == nil }
            if !missing.isEmpty {
                let (files, _) = context.codeFiles(for: target)
                let request = context.firstMatch(of: Self.healthAuthorization, in: files)
                findings.append(finding(
                    "HealthKit enabled without usage descriptions",
                    message: "'\(target.name)' has the HealthKit entitlement but no \(missing.joined(separator: " or ")). Apple's documentation says the app crashes when it requests HealthKit authorization without the usage keys, and that Xcode requires separate messages for reading and writing.",
                    severity: request != nil ? .error : .warning,
                    confidence: request != nil ? .high : .medium,
                    classification: request != nil ? .verifiedIssue : .potentialIssue,
                    file: request?.file.relativePath ?? file,
                    line: request?.line,
                    target: target,
                    evidence: missing.map { "\($0) is missing" } + (request.map { ["\($0.file.relativePath):\($0.line) requests HealthKit authorization"] } ?? []),
                    fix: "Add NSHealthShareUsageDescription and NSHealthUpdateUsageDescription for the access the app requests, or remove the HealthKit capability.",
                    documentation: "https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data"
                ))
            }
        }

        if entitlements["com.apple.security.get-task-allow"]?.boolValue == true || entitlements["get-task-allow"]?.boolValue == true {
            findings.append(finding(
                "Debugging entitlement in archived entitlements",
                message: "The entitlements file for the '\(target.configurationName)' configuration sets get-task-allow. Apple's documentation describes this as a security risk for a shipping app: Xcode strips it during a standard export, and a custom workflow that keeps it fails macOS notarization.",
                severity: .warning,
                confidence: .medium,
                classification: .potentialIssue,
                file: file,
                target: target,
                evidence: ["get-task-allow = true"],
                fix: "Remove get-task-allow from the entitlements file used for release builds and let Xcode manage it.",
                documentation: "https://developer.apple.com/documentation/security/resolving-common-notarization-issues"
            ))
        }

        if findings.isEmpty {
            findings.append(finding(
                "Entitlement values are well-formed",
                message: "'\(target.name)' has no malformed associated domains, app groups, or aps-environment values.",
                severity: .pass,
                confidence: .high,
                file: file,
                target: target
            ))
        }
        return findings
    }
}
