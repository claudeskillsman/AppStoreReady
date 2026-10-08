import Foundation
import XCTest
@testable import AppStoreReadyCore

enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static func path(_ name: String) -> String {
        root.appendingPathComponent(name).path
    }

    static func scan(_ name: String, configuration: String? = nil) throws -> ScanContext {
        try ProjectScanner(options: ScanOptions(configuration: configuration)).scan(path: path(name))
    }

    static func report(_ name: String, configuration: String? = nil, disabled: Set<String> = []) throws -> ScanReport {
        try AuditEngine.audit(path: path(name), options: ScanOptions(configuration: configuration), disabledRuleIDs: disabled)
    }
}

extension ScanReport {
    func findings(rule: String, target: String? = nil) -> [Finding] {
        findings.filter { $0.ruleID == rule && (target == nil || $0.target == target) }
    }

    func severities(rule: String, target: String? = nil) -> [Severity] {
        findings(rule: rule, target: target).map(\.severity)
    }
}

extension ScanContext {
    func target(named name: String) -> ResolvedTarget? {
        targets.first { $0.name == name }
    }
}

/// Builds a `SourceFile` without touching the file system.
func makeSourceFile(_ relativePath: String, _ contents: String, kind: SourceFile.Kind = .swift) -> SourceFile {
    let url = URL(fileURLWithPath: "/virtual").appendingPathComponent(relativePath)
    return SourceFile(url: url, path: url.path, relativePath: relativePath, kind: kind, contents: contents)
}
