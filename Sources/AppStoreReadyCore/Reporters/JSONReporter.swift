import Foundation

/// Machine-readable output with stable key ordering.
public struct JSONReporter: Reporter {
    public init() {}

    public func render(_ report: ScanReport) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(report)
        return String(decoding: data, as: UTF8.self)
    }
}
