import Foundation

/// Counts of findings by severity.
public struct ScanSummary: Codable, Equatable, Sendable {
    public var errors = 0
    public var warnings = 0
    public var manualReview = 0
    public var info = 0
    public var passes = 0

    public init(findings: [Finding]) {
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
    public let summary: ScanSummary

    public init(scannedPath: String, projects: [String], targets: [String], findings: [Finding]) {
        self.tool = "AppStoreReady"
        self.version = AppStoreReadyVersion.current
        self.scannedPath = scannedPath
        self.projects = projects
        self.targets = targets
        self.findings = findings
        self.summary = ScanSummary(findings: findings)
    }
}

public enum AppStoreReadyVersion {
    public static let current = "0.1.0"
}
