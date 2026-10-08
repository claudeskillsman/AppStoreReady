import XCTest
@testable import AppStoreReadyCore

final class RuleRegistryTests: XCTestCase {
    static let allFixtures = ["ValidApp", "MissingConfig", "Malformed", "MultiTarget", "MultiConfig", "WorkspaceApp", "Hardening", "PrivacyIssues", "MacApp", "Suppressed"]

    func testRuleIdentifiersAreUniqueAndWellFormed() {
        let ids = RuleRegistry.allMetadata.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
        for id in ids {
            XCTAssertNotNil(id.range(of: #"^ASR\d{3}$"#, options: .regularExpression), id)
        }
        XCTAssertEqual(RuleRegistry.builtIn.count, 25)
    }

    func testEveryRuleHasCompleteMetadata() {
        for metadata in RuleRegistry.allMetadata {
            XCTAssertFalse(metadata.title.isEmpty, metadata.id)
            XCTAssertGreaterThan(metadata.description.count, 40, metadata.id)
            XCTAssertGreaterThan(metadata.rationale.count, 40, metadata.id)
            XCTAssertFalse(metadata.references.isEmpty, metadata.id)
            // Placeholders such as SOME_RATIONALE must never ship.
            XCTAssertNil(metadata.rationale.range(of: #"\b[A-Z]{3,}_[A-Z_]{3,}\b"#, options: .regularExpression), metadata.id)
            for reference in metadata.references {
                let url: URL? = reference.url
                XCTAssertEqual(url?.scheme, "https", "\(metadata.id): \(reference.url)")
                XCTAssertFalse(reference.title.isEmpty, metadata.id)
                if metadata.id != "ASR000" {
                    XCTAssertEqual(url?.host, "developer.apple.com", "\(metadata.id) cites a non-Apple source: \(reference.url)")
                }
            }
        }
    }

    func testSuppressionNoticesLinkToTheReadme() {
        XCTAssertEqual(RuleRegistry.suppressionsMetadata.documentationURL?.absoluteString, "https://github.com/claudeskillsman/AppStoreReady#suppressing-findings")
        XCTAssertEqual(RuleRegistry.suppressionsMetadata.category, .manualReview)
    }

    func testEveryCategoryHasRules() {
        let used = Set(RuleRegistry.allMetadata.map(\.category))
        XCTAssertEqual(used, Set(RuleCategory.allCases))
    }

    /// Every finding in every fixture carries the fields the report promises.
    func testFindingsCarryRequiredReportFields() throws {
        let metadataByID = Dictionary(uniqueKeysWithValues: RuleRegistry.allMetadata.map { ($0.id, $0) })
        for fixture in Self.allFixtures {
            let report = try Fixtures.report(fixture)
            for finding in report.findings {
                let label = "\(fixture) \(finding.ruleID): \(finding.title)"
                let metadata = try XCTUnwrap(metadataByID[finding.ruleID], label)
                XCTAssertEqual(finding.category, metadata.category, label)
                let url = try XCTUnwrap(finding.documentationURL, label)
                XCTAssertTrue(
                    metadata.references.contains { $0.url == url } || url.absoluteString.hasPrefix("https://developer.apple.com/"),
                    label
                )
                if finding.severity == .pass {
                    XCTAssertNil(finding.suggestedFix, label)
                    XCTAssertNil(finding.classification, label)
                    continue
                }
                XCTAssertNotNil(finding.classification, label)
                XCTAssertFalse(finding.message.isEmpty, label)
                XCTAssertNotNil(finding.whyItMatters, label)
                XCTAssertNotNil(finding.suggestedFix, label)
                if finding.severity == .error || finding.severity == .warning {
                    XCTAssertTrue(finding.file != nil || !finding.evidence.isEmpty, "\(label) has no location")
                }
            }
        }
    }

    func testOnlyHighConfidenceErrorsAndWarningsAreVerified() throws {
        for fixture in Self.allFixtures {
            for finding in try Fixtures.report(fixture).findings where finding.classification == .verifiedIssue {
                XCTAssertTrue([.error, .warning].contains(finding.severity), "\(finding.ruleID): \(finding.title)")
                XCTAssertEqual(finding.confidence, .high, "\(finding.ruleID): \(finding.title)")
            }
        }
    }

    func testCustomRulesCanBePluggedIn() throws {
        struct AlwaysWarn: Rule {
            let metadata = RuleMetadata(
                id: "TEST001",
                title: "Custom",
                description: "A rule defined outside the registry.",
                rationale: "Shows that the engine runs any Rule.",
                category: .appConfiguration,
                references: [Reference("Example", "https://example.com/rule")]
            )
            func evaluate(_ context: ScanContext) -> [Finding] {
                context.targets.map { finding("Custom check", message: "Checked \($0.name)", severity: .warning, confidence: .low, target: $0) }
            }
        }
        let context = try Fixtures.scan("ValidApp")
        let report = AuditEngine(rules: [AlwaysWarn()]).run(context, scannedPath: "ValidApp")
        XCTAssertEqual(report.findings.map(\.ruleID), ["TEST001"])
        XCTAssertEqual(report.findings.first?.target, "ValidApp")
        XCTAssertEqual(report.findings.first?.configuration, "Release")
        XCTAssertEqual(report.findings.first?.classification, .potentialIssue)
        XCTAssertEqual(report.findings.first?.documentationURL?.absoluteString, "https://example.com/rule")
    }
}
