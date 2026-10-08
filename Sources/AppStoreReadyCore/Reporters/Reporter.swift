import Foundation

/// Turns a report into output for a person or another program.
public protocol Reporter {
    func render(_ report: ScanReport) throws -> String
}

public enum ReportFormat: String, CaseIterable, Sendable {
    case text
    case json
}
