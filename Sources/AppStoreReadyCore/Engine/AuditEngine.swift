import Foundation

/// Runs rules against a scanned project and assembles a report.
public struct AuditEngine {
    public let rules: [any Rule]
    public let configuration: AppStoreReadyConfiguration
    /// Today's date as `YYYY-MM-DD`, used to expire suppressions.
    public let today: String

    /// - Parameters:
    ///   - rules: Rules to run, in report order.
    ///   - disabledRuleIDs: Rule identifiers to skip (case-insensitive).
    ///   - configuration: Suppressions from `.appstoreready.yml`.
    ///   - today: Override for tests; defaults to the current UTC date.
    public init(
        rules: [any Rule] = RuleRegistry.builtIn,
        disabledRuleIDs: Set<String> = [],
        configuration: AppStoreReadyConfiguration = AppStoreReadyConfiguration(),
        today: String? = nil
    ) {
        let disabled = Set(disabledRuleIDs.map { $0.uppercased() })
        self.rules = rules.filter { !disabled.contains($0.metadata.id.uppercased()) }
        self.configuration = configuration
        self.today = today ?? AuditEngine.currentDate()
    }

    static func currentDate() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    public func run(_ context: ScanContext, scannedPath: String) -> ScanReport {
        var findings: [Finding] = []
        for rule in rules {
            let ruleFindings = rule.evaluate(context).sorted { lhs, rhs in
                (lhs.target ?? "", lhs.file ?? "", lhs.line ?? 0) < (rhs.target ?? "", rhs.file ?? "", rhs.line ?? 0)
            }
            findings += ruleFindings
        }
        let (visible, suppressed) = applySuppressions(to: findings)
        return ScanReport(
            scannedPath: scannedPath,
            projects: context.projects.map { context.relativePath($0.url) },
            targets: context.targets.map { "\($0.name) (\($0.configurationName))" },
            findings: visible,
            suppressed: suppressed
        )
    }

    /// Moves suppressed findings out of the report and adds ASR000 findings
    /// for expired, unused, and security-sensitive suppressions.
    func applySuppressions(to findings: [Finding]) -> (visible: [Finding], suppressed: [SuppressedFinding]) {
        guard !configuration.suppressions.isEmpty else { return (findings, []) }
        let meta = RuleRegistry.suppressionsMetadata
        let file = AppStoreReadyConfiguration.fileName

        func notice(_ title: String, _ message: String, severity: Severity, line: Int, evidence: [String], fix: String) -> Finding {
            Finding(
                ruleID: meta.id,
                title: title,
                message: message,
                severity: severity,
                classification: severity == .warning ? .verifiedIssue : .bestPractice,
                category: meta.category,
                confidence: .high,
                file: file,
                line: line,
                evidence: evidence,
                whyItMatters: meta.rationale,
                suggestedFix: fix,
                documentationURL: meta.documentationURL
            )
        }

        let active = configuration.suppressions.filter { !$0.isExpired(today: today) }
        var visible: [Finding] = []
        var suppressed: [SuppressedFinding] = []
        var used = Set<Int>()
        var notices: [Finding] = []

        for finding in findings {
            guard finding.severity != .pass,
                  let index = active.firstIndex(where: { $0.matches(finding) }) else {
                visible.append(finding)
                continue
            }
            let suppression = active[index]
            used.insert(index)
            suppressed.append(SuppressedFinding(finding: finding, reason: suppression.reason, expires: suppression.expires, configurationLine: suppression.line))
            if finding.category == .security && finding.severity == .error {
                let location = finding.file.map { file in finding.line.map { "\(file):\($0)" } ?? file } ?? "the project"
                notices.append(notice(
                    "Critical security finding suppressed",
                    "A suppression hides an ERROR-level security finding (\(finding.ruleID): \(finding.title)) at \(location). Suppressed security findings are always shown here so they cannot disappear silently.",
                    severity: .warning,
                    line: suppression.line,
                    evidence: ["Reason given: \(suppression.reason)"] + (suppression.expires.map { ["Expires: \($0)"] } ?? ["No expiry date"]),
                    fix: "Remove the credential instead of suppressing the finding, or add an 'expires' date so the decision is revisited."
                ))
            }
        }

        for suppression in configuration.suppressions where suppression.isExpired(today: today) {
            notices.append(notice(
                "Suppression expired",
                "The suppression of \(suppression.rule) expired on \(suppression.expires ?? "") and is no longer applied.",
                severity: .warning,
                line: suppression.line,
                evidence: ["Reason given: \(suppression.reason)"],
                fix: "Fix the underlying finding, or extend 'expires' if the reason still holds."
            ))
        }
        for (index, suppression) in active.enumerated() where !used.contains(index) {
            notices.append(notice(
                "Suppression matched nothing",
                "The suppression of \(suppression.rule)\(suppression.path.map { " for \($0)" } ?? "") did not match any finding. It may be stale.",
                severity: .info,
                line: suppression.line,
                evidence: ["Reason given: \(suppression.reason)"],
                fix: "Remove the entry if the finding no longer occurs."
            ))
        }
        return (notices.sorted { ($0.line ?? 0) < ($1.line ?? 0) } + visible, suppressed)
    }

    /// Convenience: scan a path, load `.appstoreready.yml` from the scan root
    /// (unless a configuration is given), and run all rules.
    public static func audit(
        path: String,
        options: ScanOptions = ScanOptions(),
        disabledRuleIDs: Set<String> = [],
        configuration: AppStoreReadyConfiguration? = nil,
        useConfigurationFile: Bool = true,
        today: String? = nil
    ) throws -> ScanReport {
        let context = try ProjectScanner(options: options).scan(path: path)
        var resolved = configuration ?? AppStoreReadyConfiguration()
        if configuration == nil && useConfigurationFile {
            let url = context.rootURL.appendingPathComponent(AppStoreReadyConfiguration.fileName)
            resolved = try AppStoreReadyConfiguration.load(from: url, knownRuleIDs: RuleRegistry.allRuleIDs) ?? resolved
        }
        return AuditEngine(disabledRuleIDs: disabledRuleIDs, configuration: resolved, today: today).run(context, scannedPath: path)
    }
}

/// Which findings make the process exit with a non-zero status.
public enum FailureThreshold: String, CaseIterable, Sendable {
    /// Exit 1 when any ERROR finding exists (default).
    case error
    /// Exit 1 when any ERROR or WARNING finding exists.
    case warning
    /// Always exit 0 when the scan completes.
    case never
}

/// Process exit codes used by the CLI.
public enum ExitStatus: Int32, Sendable {
    /// The scan completed and no finding reached the failure threshold.
    case success = 0
    /// The scan completed and at least one finding reached the failure threshold.
    case findings = 1
    /// The scan could not run (path not found, no project, unknown configuration,
    /// invalid `.appstoreready.yml`).
    case scanFailed = 2

    public static func forReport(_ report: ScanReport, threshold: FailureThreshold) -> ExitStatus {
        switch threshold {
        case .error:
            return report.summary.errors > 0 ? .findings : .success
        case .warning:
            return report.summary.errors + report.summary.warnings > 0 ? .findings : .success
        case .never:
            return .success
        }
    }
}
