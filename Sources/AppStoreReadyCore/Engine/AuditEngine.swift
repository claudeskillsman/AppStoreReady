import Foundation

/// Runs rules against a scanned project and assembles a report.
public struct AuditEngine {
    public let rules: [any Rule]

    /// - Parameters:
    ///   - rules: Rules to run, in report order.
    ///   - disabledRuleIDs: Rule identifiers to skip (case-insensitive).
    public init(rules: [any Rule] = RuleRegistry.builtIn, disabledRuleIDs: Set<String> = []) {
        let disabled = Set(disabledRuleIDs.map { $0.uppercased() })
        self.rules = rules.filter { !disabled.contains($0.metadata.id.uppercased()) }
    }

    public func run(_ context: ScanContext, scannedPath: String) -> ScanReport {
        var findings: [Finding] = []
        for rule in rules {
            let ruleFindings = rule.evaluate(context).sorted { lhs, rhs in
                (lhs.target ?? "", lhs.file ?? "", lhs.line ?? 0) < (rhs.target ?? "", rhs.file ?? "", rhs.line ?? 0)
            }
            findings += ruleFindings
        }
        return ScanReport(
            scannedPath: scannedPath,
            projects: context.projects.map { context.relativePath($0.url) },
            targets: context.targets.map { "\($0.name) (\($0.configurationName))" },
            findings: findings
        )
    }

    /// Convenience: scan a path and run all rules.
    public static func audit(path: String, options: ScanOptions = ScanOptions(), disabledRuleIDs: Set<String> = []) throws -> ScanReport {
        let context = try ProjectScanner(options: options).scan(path: path)
        return AuditEngine(disabledRuleIDs: disabledRuleIDs).run(context, scannedPath: path)
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
    /// The scan could not run (path not found, no project, unknown configuration).
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
