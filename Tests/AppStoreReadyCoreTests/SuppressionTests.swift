import XCTest
@testable import AppStoreReadyCore

final class SuppressionTests: XCTestCase {
    private let known = RuleRegistry.allRuleIDs

    // MARK: Parsing

    func testParsesSuppressionEntries() throws {
        let yaml = """
        # AppStoreReady settings
        version: 1
        suppressions:
          - rule: ASR008
            reason: "Demo key, restricted to the demo bundle ID"  # comment
            expires: 2027-01-31
            path: App/**/*.swift
            target: App
          - rule: asr022
            reason: dSYMs are uploaded by a separate build step
        """
        let configuration = try AppStoreReadyConfiguration.parse(yaml, knownRuleIDs: known)
        XCTAssertEqual(configuration.suppressions, [
            Suppression(rule: "ASR008", reason: "Demo key, restricted to the demo bundle ID", expires: "2027-01-31", path: "App/**/*.swift", target: "App", line: 4),
            Suppression(rule: "ASR022", reason: "dSYMs are uploaded by a separate build step", line: 9),
        ])
    }

    func testEmptyListIsAllowed() throws {
        XCTAssertEqual(try AppStoreReadyConfiguration.parse("suppressions: []\n", knownRuleIDs: known).suppressions, [])
        XCTAssertEqual(try AppStoreReadyConfiguration.parse("# nothing\n", knownRuleIDs: known).suppressions, [])
    }

    func testRejectsInvalidFiles() {
        let cases: [(String, String)] = [
            ("suppressions:\n  - rule: ASR008\n", "needs a 'reason'"),
            ("suppressions:\n  - rule: ASR999\n    reason: x\n", "Unknown rule 'ASR999'"),
            ("suppressions:\n  - reason: x\n", "missing 'rule'"),
            ("suppressions:\n  - rule: ASR008\n    reason: x\n    expires: next week\n", "YYYY-MM-DD"),
            ("suppressions:\n  - rule: ASR008\n    reason: x\n    severity: low\n", "Unknown suppression key 'severity'"),
            ("ignore:\n  - ASR008\n", "Unknown setting 'ignore'"),
            ("version: 2\n", "Unsupported version"),
            ("suppressions:\n  - rule: ASR008\n      reason: misaligned\n", "aligned"),
            ("suppressions:\n  - rule: ASR008\n    rule: ASR009\n    reason: x\n", "Duplicate key"),
            ("suppressions:\n\t- rule: ASR008\n", "tabs"),
        ]
        for (yaml, expected) in cases {
            XCTAssertThrowsError(try AppStoreReadyConfiguration.parse(yaml, knownRuleIDs: known), yaml) { error in
                let message = (error as? ConfigurationError)?.description ?? "\(error)"
                XCTAssertTrue(message.contains(expected), "\(message) should mention \(expected)")
            }
        }
    }

    func testErrorsCarryLineNumbers() {
        XCTAssertThrowsError(try AppStoreReadyConfiguration.parse("suppressions:\n  - rule: ASR008\n    reason: ok\n  - rule: ASR001\n", knownRuleIDs: known)) { error in
            XCTAssertEqual((error as? ConfigurationError)?.line, 4)
        }
    }

    // MARK: Matching

    func testGlobMatching() {
        XCTAssertTrue(Suppression.glob("App/Keys.swift", matches: "App/Keys.swift"))
        XCTAssertFalse(Suppression.glob("App/Keys.swift", matches: "App/Other.swift"))
        XCTAssertTrue(Suppression.glob("App/*.swift", matches: "App/Keys.swift"))
        XCTAssertFalse(Suppression.glob("App/*.swift", matches: "App/Sub/Keys.swift"))
        XCTAssertTrue(Suppression.glob("App/**/*.swift", matches: "App/Sub/Deep/Keys.swift"))
        XCTAssertTrue(Suppression.glob("App/**/*.swift", matches: "App/Keys.swift"))
        XCTAssertTrue(Suppression.glob("**/Demo*.swift", matches: "A/B/DemoKeys.swift"))
        XCTAssertTrue(Suppression.glob("Vendor/", matches: "Vendor/a/b.m"))
        XCTAssertFalse(Suppression.glob("App/K?ys.swift", matches: "App/Keeys.swift"))
    }

    func testExpiryIsInclusive() {
        let suppression = Suppression(rule: "ASR008", reason: "x", expires: "2026-10-08")
        XCTAssertFalse(suppression.isExpired(today: "2026-10-08"))
        XCTAssertTrue(suppression.isExpired(today: "2026-10-09"))
        XCTAssertFalse(Suppression(rule: "ASR008", reason: "x").isExpired(today: "2999-01-01"))
    }

    // MARK: Engine behavior

    private func audit(_ fixture: String, _ suppressions: [Suppression], today: String = "2026-10-08") throws -> ScanReport {
        let context = try Fixtures.scan(fixture)
        let engine = AuditEngine(configuration: AppStoreReadyConfiguration(suppressions: suppressions), today: today)
        return engine.run(context, scannedPath: fixture)
    }

    func testSuppressedFindingsAreMovedOutOfTheReport() throws {
        let report = try audit("MissingConfig", [
            Suppression(rule: "ASR009", reason: "Archive scheme is fixed in CI", line: 3),
        ])
        XCTAssertEqual(report.findings(rule: "ASR009"), [])
        XCTAssertEqual(report.suppressed.map(\.finding.ruleID), ["ASR009"])
        XCTAssertEqual(report.suppressed.first?.reason, "Archive scheme is fixed in CI")
        XCTAssertEqual(report.summary.suppressed, 1)
        XCTAssertEqual(report.findings(rule: "ASR000"), [], "a warning-level suppression needs no notice")
    }

    func testPathAndTargetNarrowSuppressions() throws {
        let report = try audit("MissingConfig", [
            Suppression(rule: "ASR008", reason: "generic match is a test value", path: "MissingConfig/APIClient.swift", line: 2),
            Suppression(rule: "ASR006", reason: "wrong target", target: "SomethingElse", line: 5),
        ])
        XCTAssertEqual(report.findings(rule: "ASR008"), [], "both ASR008 findings are in APIClient.swift")
        XCTAssertEqual(report.suppressed.count, 2)
        XCTAssertFalse(report.findings(rule: "ASR006").isEmpty, "target filter did not match")
        XCTAssertEqual(report.findings(rule: "ASR000").map(\.title), ["Critical security finding suppressed", "Suppression matched nothing"])
    }

    func testSuppressingCriticalSecurityFindingAddsVisibleWarning() throws {
        let report = try audit("MissingConfig", [
            Suppression(rule: "ASR008", reason: "AWS docs example key", expires: "2027-01-01", path: "MissingConfig/APIClient.swift", line: 7),
        ])
        let notice = try XCTUnwrap(report.findings(rule: "ASR000").first)
        XCTAssertEqual(notice.title, "Critical security finding suppressed")
        XCTAssertEqual(notice.severity, .warning)
        XCTAssertEqual(notice.file, ".appstoreready.yml")
        XCTAssertEqual(notice.line, 7)
        XCTAssertTrue(notice.message.contains("MissingConfig/APIClient.swift:5"))
        XCTAssertTrue(notice.evidence.contains("Reason given: AWS docs example key"))
        XCTAssertEqual(ExitStatus.forReport(report, threshold: .warning), .findings)
        // The report text still never contains the secret.
        XCTAssertFalse(TextReporter(verbose: true).render(report).contains("AKIAIOSFODNN7EXAMPLE"))
        XCTAssertFalse(try JSONReporter().render(report).contains("AKIAIOSFODNN7EXAMPLE"))
    }

    func testExpiredSuppressionsAreNotApplied() throws {
        let report = try audit("MissingConfig", [
            Suppression(rule: "ASR009", reason: "temporary", expires: "2026-01-31", line: 2),
        ], today: "2026-10-08")
        XCTAssertFalse(report.findings(rule: "ASR009").isEmpty)
        XCTAssertEqual(report.suppressed.count, 0)
        let notice = try XCTUnwrap(report.findings(rule: "ASR000").first)
        XCTAssertEqual(notice.title, "Suppression expired")
        XCTAssertEqual(notice.severity, .warning)
    }

    func testPassingChecksAreNeverSuppressed() throws {
        let report = try audit("ValidApp", [Suppression(rule: "ASR002", reason: "x", line: 1)])
        XCTAssertEqual(report.severities(rule: "ASR002"), [.pass])
        XCTAssertEqual(report.findings(rule: "ASR000").map(\.title), ["Suppression matched nothing"])
    }

    func testTextReportListsSuppressedFindings() throws {
        let report = try audit("MissingConfig", [Suppression(rule: "ASR009", reason: "Archive scheme is fixed in CI", line: 3)])
        let text = TextReporter().render(report)
        XCTAssertTrue(text.contains("Suppressed by .appstoreready.yml (1):"))
        XCTAssertTrue(text.contains("Reason: Archive scheme is fixed in CI"))
        XCTAssertTrue(text.contains("1 finding suppressed."))
    }

    func testConfigurationFileIsLoadedFromScanRoot() throws {
        let report = try Fixtures.report("Suppressed", today: "2026-10-08")
        XCTAssertEqual(report.suppressed.map(\.finding.ruleID), ["ASR008"])
        XCTAssertEqual(Set(report.findings(rule: "ASR000").map(\.title)), ["Critical security finding suppressed", "Suppression expired"])
    }

    func testInvalidConfigurationFileStopsTheScan() {
        XCTAssertThrowsError(try Fixtures.report("SuppressedInvalid")) { error in
            XCTAssertTrue(error is ConfigurationError)
        }
    }

    func testConfigurationFileCanBeIgnored() throws {
        let report = try AuditEngine.audit(path: Fixtures.path("Suppressed"), useConfigurationFile: false)
        XCTAssertEqual(report.suppressed.count, 0)
        XCTAssertEqual(report.severities(rule: "ASR008"), [.error])
    }
}
