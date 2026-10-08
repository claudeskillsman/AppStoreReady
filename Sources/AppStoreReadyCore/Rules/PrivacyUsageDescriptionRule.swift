import Foundation

/// ASR006: APIs that access protected resources need a purpose string.
public struct PrivacyUsageDescriptionRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR006",
        title: "Privacy usage descriptions",
        description: "Looks for source code that requests access to protected resources (camera, location, photos, contacts, and others) and checks that the matching purpose string (for example NSCameraUsageDescription) is present and not empty.",
        category: .privacy,
        documentationURL: URL(string: "https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources")
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.flatMap { evaluate($0, context: context) }
    }

    private func evaluate(_ target: ResolvedTarget, context: ScanContext) -> [Finding] {
        guard let info = target.infoPlist, !info.isUnreadable else { return [] }
        let (files, exact) = context.codeFiles(for: target)
        var findings: [Finding] = []
        var satisfied: [String] = []

        for resource in APIUsageCatalog.protectedResources {
            let strong = context.firstMatch(of: resource.strongPatterns, in: files)
            let weak = strong == nil ? context.firstMatch(of: resource.weakPatterns, in: files) : nil
            guard let match = strong ?? weak else { continue }

            if let presentKey = resource.keys.first(where: { info.resolved[$0] != nil }) {
                satisfied.append(resource.name)
                if let value = info.string(presentKey), value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    findings.append(finding(
                        "Empty privacy usage description",
                        message: "\(presentKey) is present but empty. The purpose string is shown to people when the app asks for access, so it must explain why the app needs it.",
                        severity: .warning,
                        confidence: .high,
                        file: context.infoPlistLocation(for: target, key: presentKey),
                        target: target,
                        evidence: ["\(presentKey) = \"\""],
                        fix: "Write a clear, specific sentence describing how the app uses \(resource.name.lowercased()) data."
                    ))
                }
                continue
            }

            let isStrong = strong != nil
            var evidence = ["\(match.file.relativePath):\(match.line) uses \(resource.name) APIs"]
            if !exact {
                evidence.append("Target membership could not be determined; all source files under the scan root were searched.")
            }
            findings.append(finding(
                isStrong ? "Missing privacy usage description" : "Privacy usage descriptions need review",
                message: isStrong
                    ? "'\(target.name)' appears to request access to \(resource.name) but its Info.plist has no \(resource.keys.joined(separator: " or ")). Apple's documentation states that access attempts without a purpose string fail and might crash the app, and that App Review rejects apps containing code that accesses protected resources without one."
                    : "'\(target.name)' references \(resource.name) APIs but its Info.plist has no \(resource.keys.joined(separator: " or ")). Check whether the app requests access; if it does, a purpose string is needed.",
                severity: isStrong ? .error : .warning,
                confidence: isStrong && exact ? .medium : .low,
                file: match.file.relativePath,
                line: match.line,
                target: target,
                evidence: evidence,
                fix: "Add \(resource.keys[0]) to the Info.plist (or INFOPLIST_KEY_\(resource.keys[0]) in build settings) with a sentence explaining why the app needs access."
            ))
        }

        // Purpose strings that exist but are blank or obviously unfinished.
        let detectedKeys = Set(APIUsageCatalog.protectedResources.filter { satisfied.contains($0.name) }.flatMap(\.keys))
        for key in info.resolved.keys.sorted() where key.hasSuffix("UsageDescription") && !detectedKeys.contains(key) {
            let value = info.string(key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let lowered = value.lowercased()
            if value.isEmpty || lowered == "todo" || lowered.hasPrefix("todo") || lowered == "tbd" || lowered.contains("lorem ipsum") {
                findings.append(finding(
                    "Placeholder privacy usage description",
                    message: "\(key) is empty or looks unfinished.",
                    severity: .warning,
                    confidence: .high,
                    file: context.infoPlistLocation(for: target, key: key),
                    target: target,
                    evidence: ["\(key) = \"\(value)\""],
                    fix: "Replace it with a sentence that explains why the app needs this access, or remove the key if the app does not use it."
                ))
            }
        }

        if findings.isEmpty {
            findings.append(finding(
                satisfied.isEmpty ? "No protected-resource API usage detected" : "Privacy usage descriptions present",
                message: satisfied.isEmpty
                    ? "No source code in '\(target.name)' appears to request protected resources. Binary SDKs are not inspected."
                    : "Purpose strings are present for the protected resources '\(target.name)' appears to use.",
                severity: .pass,
                confidence: satisfied.isEmpty ? .low : .medium,
                file: context.infoPlistLocation(for: target, key: "CFBundleIdentifier"),
                target: target,
                evidence: satisfied.map { "\($0): purpose string present" }
            ))
        }
        return findings
    }
}
