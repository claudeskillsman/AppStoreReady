import Foundation

/// ASR019: UIBackgroundModes and BGTaskScheduler configuration.
public struct BackgroundModesRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR019",
        title: "Background modes",
        description: "Checks UIBackgroundModes values against Apple's documented list, checks that BGTaskScheduler identifiers registered in code are listed in BGTaskSchedulerPermittedIdentifiers, and asks for review of declared background modes under App Review Guideline 2.5.4.",
        rationale: "BGTaskScheduler refuses to register identifiers that are not listed in BGTaskSchedulerPermittedIdentifiers, and Apple's documentation says every listed identifier requires a handler. Guideline 2.5.4 says apps may only use background services for their intended purposes.",
        category: .appConfiguration,
        references: [
            Reference("UIBackgroundModes", "https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes"),
            Reference("BGTaskSchedulerPermittedIdentifiers", "https://developer.apple.com/documentation/bundleresources/information-property-list/bgtaskschedulerpermittedidentifiers"),
            Reference("register(forTaskWithIdentifier:using:launchHandler:)", "https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:)"),
            Reference("App Review Guideline 2.5.4", "https://developer.apple.com/app-store/review/guidelines/#software-requirements"),
        ]
    )

    /// Values listed on the UIBackgroundModes page, plus workout-processing from Xcode's capability table.
    static let knownModes: Set<String> = [
        "audio", "bluetooth-central", "bluetooth-peripheral", "external-accessory", "fetch", "location",
        "nearby-interaction", "network-authentication", "newsstand-content", "processing", "push-to-talk",
        "remote-notification", "screen-capture", "voip", "workout-processing",
    ]
    static let register = TextPattern(#"register\s*\(\s*forTaskWithIdentifier\s*:\s*"([^"]+)""#)
    static let objcRegister = TextPattern(#"registerForTaskWithIdentifier\s*:\s*@"([^"]+)""#)

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.filter { !$0.sdk.hasPrefix("macosx") }.flatMap { evaluate($0, context: context) }
    }

    private func evaluate(_ target: ResolvedTarget, context: ScanContext) -> [Finding] {
        guard let info = target.infoPlist, !info.isUnreadable else { return [] }
        var findings: [Finding] = []
        let modes = info.resolved["UIBackgroundModes"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let permitted = info.resolved["BGTaskSchedulerPermittedIdentifiers"]?.arrayValue?.compactMap(\.stringValue)
        let modesFile = context.infoPlistLocation(for: target, key: "UIBackgroundModes")

        let unknown = modes.filter { !Self.knownModes.contains($0) }
        if !unknown.isEmpty {
            findings.append(finding(
                "Unknown background mode",
                message: "'\(target.name)' declares UIBackgroundModes values that are not in Apple's documented list.",
                severity: .warning,
                confidence: .high,
                classification: .verifiedIssue,
                file: modesFile,
                target: target,
                evidence: unknown.map { "UIBackgroundModes: '\($0)'" },
                fix: "Remove these values or correct their spelling (for example remote-notification, processing, fetch)."
            ))
        }

        // Identifiers registered in code with string literals.
        let (files, _) = context.codeFiles(for: target)
        var registered: [(id: String, file: String, line: Int)] = []
        for file in files where !isTestPath(file.relativePath) {
            for (index, line) in file.lines.enumerated() where !SourceText.isCommentLine(line) {
                let text = String(line)
                for match in Self.register.allMatches(in: text) + Self.objcRegister.allMatches(in: text) {
                    if let id = match[1] { registered.append((id, file.relativePath, index + 1)) }
                }
            }
        }
        if !registered.isEmpty {
            let allowed = Set(permitted ?? [])
            let unlisted = registered.filter { !allowed.contains($0.id) }
            if let first = unlisted.first {
                findings.append(finding(
                    "Background task identifier not permitted",
                    message: "'\(target.name)' registers background task identifiers that are not in BGTaskSchedulerPermittedIdentifiers. Apple's documentation says registration returns false for identifiers missing from that list, so these tasks never run.",
                    severity: .error,
                    confidence: .high,
                    classification: .verifiedIssue,
                    file: first.file,
                    line: first.line,
                    target: target,
                    evidence: unlisted.map { "\($0.file):\($0.line) registers '\($0.id)'" },
                    fix: "Add each identifier to BGTaskSchedulerPermittedIdentifiers in Info.plist.",
                    documentation: "https://developer.apple.com/documentation/bundleresources/information-property-list/bgtaskschedulerpermittedidentifiers"
                ))
            }
            let registeredIDs = Set(registered.map(\.id))
            let unhandled = (permitted ?? []).filter { !registeredIDs.contains($0) && !$0.contains("$(") && !$0.hasSuffix("*") }
            if !unhandled.isEmpty {
                findings.append(finding(
                    "Permitted background task without a handler",
                    message: "Apple's documentation says every identifier in BGTaskSchedulerPermittedIdentifiers requires a handler, but no registration with these identifiers was found in '\(target.name)'.",
                    severity: .warning,
                    confidence: .medium,
                    classification: .potentialIssue,
                    file: context.infoPlistLocation(for: target, key: "BGTaskSchedulerPermittedIdentifiers"),
                    target: target,
                    evidence: unhandled.map { "BGTaskSchedulerPermittedIdentifiers: '\($0)'" },
                    fix: "Register a launch handler for each identifier, or remove identifiers that are no longer used.",
                    documentation: "https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler/register(fortaskwithidentifier:using:launchhandler:)"
                ))
            }
        }
        if permitted?.isEmpty == false, !modes.contains("fetch"), !modes.contains("processing") {
            findings.append(finding(
                "Background tasks without a background mode",
                message: "'\(target.name)' lists BGTaskSchedulerPermittedIdentifiers but UIBackgroundModes contains neither fetch nor processing. Apple's documentation says to select Background fetch for BGAppRefreshTask and Background processing for BGProcessingTask.",
                severity: .warning,
                confidence: .medium,
                classification: .potentialIssue,
                file: modesFile,
                target: target,
                evidence: ["UIBackgroundModes: \(modes.isEmpty ? "(none)" : modes.joined(separator: ", "))"],
                fix: "Enable Background fetch or Background processing in the Background Modes capability, matching the task types the app schedules.",
                documentation: "https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes"
            ))
        }

        let known = modes.filter { Self.knownModes.contains($0) }
        if !known.isEmpty {
            findings.append(finding(
                "Background modes need review (Guideline 2.5.4)",
                message: "'\(target.name)' declares background modes. Guideline 2.5.4 says apps may only use background services for their intended purposes, which App Review checks against the app's behavior.",
                severity: .manualReview,
                confidence: .high,
                file: modesFile,
                target: target,
                evidence: known.map { "UIBackgroundModes: \($0)" },
                fix: "Make sure each mode is used for its intended purpose, remove modes the app does not need, and explain non-obvious uses in the App Review notes.",
                documentation: "https://developer.apple.com/app-store/review/guidelines/#software-requirements"
            ))
        }
        return findings
    }
}
