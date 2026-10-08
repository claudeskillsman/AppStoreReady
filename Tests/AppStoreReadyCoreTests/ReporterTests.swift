import XCTest
@testable import AppStoreReadyCore

final class ReporterTests: XCTestCase {
    private func sampleReport() -> ScanReport {
        ScanReport(scannedPath: "./MyApp", projects: ["MyApp.xcodeproj"], targets: ["MyApp (Release)"], findings: [
            Finding(ruleID: "ASR005", title: "App icon configuration detected", message: "ok", severity: .pass, category: .assets, confidence: .high, target: "MyApp"),
            Finding(ruleID: "ASR006", title: "Privacy usage descriptions need review", message: "check", severity: .warning, category: .privacy, confidence: .low, file: "A.swift", line: 3, target: "MyApp", evidence: ["A.swift:3 uses Camera APIs"], suggestedFix: "Add the key."),
            Finding(ruleID: "ASR008", title: "Potential hardcoded secret detected", message: "bad", severity: .error, category: .security, confidence: .high, file: "B.swift", line: 9, documentationURL: URL(string: "https://example.com/docs")),
            Finding(ruleID: "ASR010", title: "Accessibility audit requires runtime testing", message: "test it", severity: .info, category: .accessibility, confidence: .high),
        ])
    }

    func testTextReportMatchesDocumentedShape() {
        let text = TextReporter(useColor: false).render(sampleReport())
        XCTAssertTrue(text.hasPrefix("AppStoreReady — iOS App Audit"))
        XCTAssertTrue(text.contains("PASS    App icon configuration detected  [MyApp]"))
        XCTAssertTrue(text.contains("WARN    Privacy usage descriptions need review  [MyApp]"))
        XCTAssertTrue(text.contains("FAIL    Potential hardcoded secret detected"))
        XCTAssertTrue(text.contains("INFO    Accessibility audit requires runtime testing"))
        XCTAssertTrue(text.contains("File: B.swift:9"))
        XCTAssertTrue(text.contains("Rule ASR008 · confidence high · https://example.com/docs"))
        XCTAssertTrue(text.contains("Summary: 1 failure, 1 warning, 1 manual review item."))
        XCTAssertTrue(text.contains("1 check passed."))
        XCTAssertFalse(text.contains("\u{1B}["), "no ANSI codes without color")
    }

    func testPassDetailsOnlyInVerboseMode() {
        let quiet = TextReporter().render(sampleReport())
        let verbose = TextReporter(verbose: true).render(sampleReport())
        XCTAssertFalse(quiet.contains("        ok"))
        XCTAssertTrue(verbose.contains("        ok"))
    }

    func testColorOutputUsesANSICodes() {
        XCTAssertTrue(TextReporter(useColor: true).render(sampleReport()).contains("\u{1B}[1;31mFAIL"))
    }

    func testSummaryPluralization() {
        let report = ScanReport(scannedPath: ".", projects: [], targets: [], findings: [])
        XCTAssertTrue(TextReporter().render(report).contains("Summary: 0 failures, 0 warnings, 0 manual review items."))
    }

    func testJSONRoundTrips() throws {
        let original = sampleReport()
        let json = try JSONReporter().render(original)
        let decoded = try JSONDecoder().decode(ScanReport.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.findings, original.findings)
        XCTAssertEqual(decoded.summary, original.summary)
        XCTAssertEqual(decoded.tool, "AppStoreReady")
        XCTAssertTrue(json.contains("\"severity\" : \"MANUAL_REVIEW\"") || json.contains("\"severity\" : \"INFO\""))
        XCTAssertTrue(json.contains("\"documentationURL\" : \"https://example.com/docs\""))
    }

    func testSummaryCounts() {
        let summary = sampleReport().summary
        XCTAssertEqual(summary.errors, 1)
        XCTAssertEqual(summary.warnings, 1)
        XCTAssertEqual(summary.info, 1)
        XCTAssertEqual(summary.passes, 1)
        XCTAssertEqual(summary.manualReview, 0)
    }

    func testExitStatusThresholds() {
        let report = sampleReport()
        XCTAssertEqual(ExitStatus.forReport(report, threshold: .error), .findings)
        XCTAssertEqual(ExitStatus.forReport(report, threshold: .never), .success)

        let warningsOnly = ScanReport(scannedPath: ".", projects: [], targets: [], findings: report.findings.filter { $0.severity != .error })
        XCTAssertEqual(ExitStatus.forReport(warningsOnly, threshold: .error), .success)
        XCTAssertEqual(ExitStatus.forReport(warningsOnly, threshold: .warning), .findings)
        XCTAssertEqual(ExitStatus.scanFailed.rawValue, 2)
    }

    func testSeverityOrderingAndLabels() {
        XCTAssertEqual([Severity.pass, .info, .error, .manualReview, .warning].sorted(), [.error, .warning, .manualReview, .info, .pass])
        XCTAssertEqual(Severity.allCases.map(\.rawValue), ["PASS", "WARNING", "ERROR", "INFO", "MANUAL_REVIEW"])
        XCTAssertEqual(Severity.error.label, "FAIL")
        XCTAssertEqual(Severity.warning.label, "WARN")
    }
}
