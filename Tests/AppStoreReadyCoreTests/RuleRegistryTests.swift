import XCTest
@testable import AppStoreReadyCore

final class RuleRegistryTests: XCTestCase {
    func testRuleIdentifiersAreUniqueAndWellFormed() {
        let ids = RuleRegistry.builtIn.map(\.metadata.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        for id in ids {
            XCTAssertNotNil(id.range(of: #"^ASR\d{3}$"#, options: .regularExpression), id)
        }
    }

    func testEveryRuleHasCompleteMetadata() {
        for rule in RuleRegistry.builtIn {
            let metadata = rule.metadata
            XCTAssertFalse(metadata.title.isEmpty, metadata.id)
            XCTAssertGreaterThan(metadata.description.count, 40, metadata.id)
            XCTAssertEqual(metadata.documentationURL?.scheme, "https", metadata.id)
        }
    }

    func testFindingsCarryRuleMetadata() throws {
        let report = try Fixtures.report("MissingConfig")
        let byID = Dictionary(uniqueKeysWithValues: RuleRegistry.builtIn.map { ($0.metadata.id, $0.metadata) })
        for finding in report.findings {
            let metadata = try XCTUnwrap(byID[finding.ruleID])
            XCTAssertEqual(finding.category, metadata.category)
            XCTAssertEqual(finding.documentationURL, metadata.documentationURL)
            if finding.severity == .error || finding.severity == .warning {
                XCTAssertNotNil(finding.suggestedFix, "\(finding.ruleID): \(finding.title)")
            }
            if finding.severity == .pass {
                XCTAssertNil(finding.suggestedFix)
            }
        }
    }

    func testCustomRulesCanBePluggedIn() throws {
        struct AlwaysWarn: Rule {
            let metadata = RuleMetadata(id: "TEST001", title: "Custom", description: "A rule defined outside the registry.", category: .configuration, documentationURL: nil)
            func evaluate(_ context: ScanContext) -> [Finding] {
                context.targets.map { finding("Custom check", message: "Checked \($0.name)", severity: .warning, confidence: .low, target: $0) }
            }
        }
        let context = try Fixtures.scan("ValidApp")
        let report = AuditEngine(rules: [AlwaysWarn()]).run(context, scannedPath: "ValidApp")
        XCTAssertEqual(report.findings.map(\.ruleID), ["TEST001"])
        XCTAssertEqual(report.findings.first?.target, "ValidApp")
        XCTAssertEqual(report.findings.first?.configuration, "Release")
    }
}
