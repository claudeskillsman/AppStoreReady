import Foundation

/// Counts of findings by severity.
public struct ScanSummary: Codable, Equatable, Sendable {
    public var errors = 0
    public var warnings = 0
    public var manualReview = 0
    public var info = 0
    public var passes = 0
    /// Findings hidden by `.appstoreready.yml`; not included in the other counts.
    public var suppressed = 0

    public init(findings: [Finding], suppressed: Int = 0) {
        self.suppressed = suppressed
        for finding in findings {
            switch finding.severity {
            case .error: errors += 1
            case .warning: warnings += 1
            case .manualReview: manualReview += 1
            case .info: info += 1
            case .pass: passes += 1
            }
        }
    }
}

/// A finding hidden by a suppression in `.appstoreready.yml`.
public struct SuppressedFinding: Codable, Equatable, Sendable {
    public let finding: Finding
    public let reason: String
    public let expires: String?
    /// Line of the suppression in the configuration file.
    public let configurationLine: Int
}

/// The complete result of a scan.
public struct ScanReport: Codable, Sendable {
    public let tool: String
    public let version: String
    /// The path the user asked to scan, as given.
    public let scannedPath: String
    /// Xcode projects that were analysed, relative to the scan root.
    public let projects: [String]
    /// Targets that were analysed, as `Target (Configuration)`.
    public let targets: [String]
    public let findings: [Finding]
    /// Findings hidden by suppressions. Always reported so nothing disappears silently.
    public let suppressed: [SuppressedFinding]
    public let summary: ScanSummary

    public init(scannedPath: String, projects: [String], targets: [String], findings: [Finding], suppressed: [SuppressedFinding] = []) {
        self.tool = "AppStoreReady"
        self.version = AppStoreReadyVersion.current
        self.scannedPath = scannedPath
        self.projects = projects
        self.targets = targets
        self.findings = findings
        self.suppressed = suppressed
        self.summary = ScanSummary(findings: findings, suppressed: suppressed.count)
    }
}

public enum AppStoreReadyVersion {
    public static let current = "0.2.0"
}
