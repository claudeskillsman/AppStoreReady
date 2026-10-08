import Foundation

/// Human-readable terminal output.
public struct TextReporter: Reporter {
    public var useColor: Bool
    /// Show details (message, evidence, documentation) for passing checks too.
    public var verbose: Bool

    public init(useColor: Bool = false, verbose: Bool = false) {
        self.useColor = useColor
        self.verbose = verbose
    }

    public func render(_ report: ScanReport) -> String {
        var lines: [String] = []
        lines.append(bold("AppStoreReady — iOS App Audit"))
        lines.append("")
        lines.append(dim("Scanned \(report.scannedPath)"))
        for project in report.projects {
            lines.append(dim("  Project: \(project)"))
        }
        for target in report.targets {
            lines.append(dim("  Target:  \(target)"))
        }
        lines.append("")

        for finding in report.findings {
            var title = finding.title
            if let target = finding.target {
                title += dim("  [\(target)]")
            }
            lines.append("\(badge(finding.severity))  \(title)")

            let showDetails = verbose || finding.severity != .pass
            guard showDetails else { continue }
            let indent = "        "
            lines.append(indent + finding.message)
            if let file = finding.file {
                let location = finding.line.map { "\(file):\($0)" } ?? file
                lines.append(indent + dim("File: \(location)"))
            }
            for item in finding.evidence {
                lines.append(indent + dim("• \(item)"))
            }
            if let why = finding.whyItMatters, verbose || finding.severity == .error || finding.severity == .warning {
                lines.append(indent + "Why: \(why)")
            }
            if let fix = finding.suggestedFix {
                lines.append(indent + "Fix: \(fix)")
            }
            var meta = "Rule \(finding.ruleID)"
            if let classification = finding.classification {
                meta += " · \(classification.displayName)"
            }
            meta += " · confidence \(finding.confidence.rawValue)"
            if let url = finding.documentationURL {
                meta += " · \(url.absoluteString)"
            }
            lines.append(indent + dim(meta))
        }

        if !report.suppressed.isEmpty {
            lines.append("")
            lines.append(bold("Suppressed by \(AppStoreReadyConfiguration.fileName) (\(report.suppressed.count)):"))
            for item in report.suppressed {
                let location = item.finding.file.map { file in item.finding.line.map { "\(file):\($0)" } ?? file }
                var line = "  \(item.finding.severity.label.padding(toLength: 6, withPad: " ", startingAt: 0))  \(item.finding.ruleID) \(item.finding.title)"
                if let location { line += dim("  [\(location)]") }
                lines.append(line)
                lines.append(dim("          Reason: \(item.reason)" + (item.expires.map { " · expires \($0)" } ?? "")))
            }
        }

        let summary = report.summary
        lines.append("")
        lines.append(bold("Summary: \(count(summary.errors, "failure")), \(count(summary.warnings, "warning")), \(count(summary.info, "recommendation")), \(count(summary.manualReview, "manual review item"))."))
        var passed = "\(count(summary.passes, "check")) passed."
        if summary.suppressed > 0 {
            passed += " \(count(summary.suppressed, "finding")) suppressed."
        }
        lines.append(dim(passed))
        lines.append(dim("AppStoreReady reports likely problems found by static analysis. It cannot predict App Review decisions."))
        return lines.joined(separator: "\n")
    }

    private func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }

    private func badge(_ severity: Severity) -> String {
        let label = severity.label.padding(toLength: 6, withPad: " ", startingAt: 0)
        guard useColor else { return label }
        let code: String
        switch severity {
        case .pass: code = "32"
        case .warning: code = "33"
        case .error: code = "31"
        case .info: code = "36"
        case .manualReview: code = "35"
        }
        return "\u{1B}[1;\(code)m\(label)\u{1B}[0m"
    }

    private func bold(_ text: String) -> String {
        useColor ? "\u{1B}[1m\(text)\u{1B}[0m" : text
    }

    private func dim(_ text: String) -> String {
        useColor ? "\u{1B}[2m\(text)\u{1B}[0m" : text
    }
}
