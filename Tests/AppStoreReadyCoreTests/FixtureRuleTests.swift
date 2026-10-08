import XCTest
@testable import AppStoreReadyCore

/// End-to-end rule behavior on the fixture projects.
final class FixtureRuleTests: XCTestCase {
    // MARK: Valid configuration

    func testValidAppHasNoFailuresOrWarnings() throws {
        let report = try Fixtures.report("ValidApp")
        let problems = report.findings.filter { $0.severity == .error || $0.severity == .warning }
        XCTAssertEqual(problems, [], "unexpected: \(problems.map(\.title))")
        XCTAssertEqual(report.summary.errors, 0)
        XCTAssertEqual(report.summary.warnings, 0)
        for rule in ["ASR001", "ASR002", "ASR003", "ASR004", "ASR005", "ASR006", "ASR007", "ASR008", "ASR009"] {
            XCTAssertEqual(report.severities(rule: rule), [.pass], rule)
        }
        XCTAssertEqual(report.severities(rule: "ASR010"), [.info])
        XCTAssertEqual(ExitStatus.forReport(report, threshold: .warning), .success)
    }

    func testValidAppPassEvidenceNamesDetectedAPIs() throws {
        let report = try Fixtures.report("ValidApp")
        XCTAssertEqual(report.findings(rule: "ASR006").first?.evidence, ["Location (when in use): purpose string present"])
        XCTAssertEqual(report.findings(rule: "ASR007").first?.evidence, ["NSPrivacyAccessedAPICategoryUserDefaults declared"])
    }

    // MARK: Missing configuration

    func testMissingConfigurationIsReported() throws {
        let report = try Fixtures.report("MissingConfig")
        XCTAssertEqual(report.severities(rule: "ASR002"), [.error])
        XCTAssertEqual(report.findings(rule: "ASR002").first?.title, "Missing bundle identifier")
        XCTAssertTrue(report.findings(rule: "ASR002")[0].evidence.contains { $0.contains("$(PRODUCT_BUNDLE_IDENTIFIER)") && $0.contains("not set") })

        XCTAssertEqual(report.findings(rule: "ASR003").map(\.title), ["Missing version number"])
        XCTAssertEqual(report.findings(rule: "ASR004").map(\.title), ["Missing build number"])
        XCTAssertEqual(report.findings(rule: "ASR005").map(\.title), ["Missing app icon configuration"])
        XCTAssertEqual(report.severities(rule: "ASR005"), [.error])
    }

    func testMissingCameraPurposeStringIsAnErrorWithLocation() throws {
        let report = try Fixtures.report("MissingConfig")
        let missing = report.findings(rule: "ASR006").filter { $0.title == "Missing privacy usage description" }
        XCTAssertEqual(missing.count, 1)
        XCTAssertEqual(missing.first?.severity, .error)
        XCTAssertEqual(missing.first?.file, "MissingConfig/CameraViewController.swift")
        XCTAssertEqual(missing.first?.line, 7)
        XCTAssertTrue(missing.first?.message.contains("NSCameraUsageDescription") ?? false)
    }

    func testEmptyPurposeStringIsAWarning() throws {
        let report = try Fixtures.report("MissingConfig")
        let placeholder = report.findings(rule: "ASR006").filter { $0.title == "Placeholder privacy usage description" }
        XCTAssertEqual(placeholder.map(\.severity), [.warning])
        XCTAssertEqual(placeholder.first?.file, "MissingConfig/Info.plist")
    }

    func testRequiredReasonAPIWithoutManifestIsAnError() throws {
        let report = try Fixtures.report("MissingConfig")
        let finding = try XCTUnwrap(report.findings(rule: "ASR007").first)
        XCTAssertEqual(finding.title, "Missing privacy manifest")
        XCTAssertEqual(finding.severity, .error)
        XCTAssertEqual(finding.file, "MissingConfig/Settings.swift")
        XCTAssertTrue(finding.evidence[0].contains("NSPrivacyAccessedAPICategoryUserDefaults"))
    }

    func testSecretsAreFoundAndSuppressionIsHonored() throws {
        let report = try Fixtures.report("MissingConfig")
        let secrets = report.findings(rule: "ASR008")
        XCTAssertEqual(secrets.map(\.line), [5, 6])
        XCTAssertEqual(secrets.map(\.severity), [.error, .warning])
        XCTAssertFalse(secrets.contains { $0.line == 7 }, "line 7 carries appstoreready:ignore")
    }

    func testDebugArchiveSchemeIsReported() throws {
        let report = try Fixtures.report("MissingConfig")
        let finding = try XCTUnwrap(report.findings(rule: "ASR009").first)
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertEqual(finding.confidence, .high)
        XCTAssertTrue(finding.evidence.contains("Scheme 'MissingConfig' archives with the 'Debug' configuration"))
        XCTAssertEqual(finding.file, "MissingConfig.xcodeproj/xcshareddata/xcschemes/MissingConfig.xcscheme")
    }

    func testMissingConfigExitsWithFailure() throws {
        let report = try Fixtures.report("MissingConfig")
        XCTAssertEqual(ExitStatus.forReport(report, threshold: .error), .findings)
        XCTAssertEqual(ExitStatus.forReport(report, threshold: .never), .success)
    }

    // MARK: Malformed files

    func testMalformedFilesAreReportedOnceAndDependentChecksSkipped() throws {
        let report = try Fixtures.report("Malformed")
        let parse = report.findings(rule: "ASR001")
        XCTAssertEqual(Set(parse.compactMap(\.file)), [
            "Malformed/Info.plist",
            "Malformed/PrivacyInfo.xcprivacy",
            "Malformed/Assets.xcassets/AppIcon.appiconset/Contents.json",
        ])
        XCTAssertEqual(parse.first { $0.file == "Malformed/Info.plist" }?.severity, .error)
        XCTAssertEqual(parse.first { $0.file?.hasSuffix("Contents.json") == true }?.severity, .warning)
        // Checks that need the unreadable files report nothing instead of guessing.
        for rule in ["ASR002", "ASR003", "ASR004", "ASR005", "ASR006", "ASR007"] {
            XCTAssertEqual(report.findings(rule: rule), [], rule)
        }
    }

    func testBrokenProjectFileFailsWithoutCrashing() throws {
        let report = try Fixtures.report("BrokenProject")
        XCTAssertEqual(report.severities(rule: "ASR001"), [.error])
        XCTAssertTrue(report.findings(rule: "ASR001")[0].message.contains("could not be parsed"))
        XCTAssertEqual(report.findings(rule: "ASR010"), [], "no app targets, no accessibility reminder")
        XCTAssertEqual(ExitStatus.forReport(report, threshold: .error), .findings)
    }

    // MARK: Multiple targets

    func testMultipleTargetsAreEvaluatedSeparately() throws {
        let report = try Fixtures.report("MultiTarget")
        XCTAssertEqual(report.severities(rule: "ASR002", target: "Shop"), [.pass])
        XCTAssertEqual(report.severities(rule: "ASR002", target: "ShopWidget"), [.pass])
        XCTAssertTrue(report.findings.allSatisfy { $0.target != "ShopKit" && $0.target != "ShopTests" })
        // App icons are checked for applications only.
        XCTAssertEqual(report.findings(rule: "ASR005").compactMap(\.target), ["Shop"])
    }

    func testExtensionVersionMismatchIsAWarning() throws {
        let report = try Fixtures.report("MultiTarget")
        let finding = try XCTUnwrap(report.findings(rule: "ASR003", target: "ShopWidget").first)
        XCTAssertEqual(finding.title, "Extension version differs from the app")
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertEqual(report.severities(rule: "ASR004", target: "ShopWidget"), [.pass])
    }

    func testManifestOutsideTargetIsReported() throws {
        let report = try Fixtures.report("MultiTarget")
        XCTAssertEqual(report.severities(rule: "ASR007", target: "Shop"), [.pass])
        let widget = try XCTUnwrap(report.findings(rule: "ASR007", target: "ShopWidget").first)
        XCTAssertEqual(widget.title, "Privacy manifest not included in target")
        XCTAssertEqual(widget.severity, .error)
    }

    func testExcludedSynchronizedFileDoesNotTriggerPurposeString() throws {
        let report = try Fixtures.report("MultiTarget")
        XCTAssertEqual(report.severities(rule: "ASR006", target: "ShopWidget"), [.pass])
    }

    func testSecretsInTestsAreDowngraded() throws {
        let report = try Fixtures.report("MultiTarget")
        let finding = try XCTUnwrap(report.findings(rule: "ASR008").first)
        XCTAssertEqual(finding.file, "ShopTests/CartTests.swift")
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertEqual(finding.confidence, .low)
    }

    func testTargetWithoutSchemeGetsInfo() throws {
        let report = try Fixtures.report("MultiTarget")
        let info = report.findings(rule: "ASR009").filter { $0.severity == .info }
        XCTAssertEqual(info.compactMap(\.target), ["ShopWidget"])
    }

    // MARK: Multiple build configurations

    func testStagingArchiveConfigurationIsFlagged() throws {
        let report = try Fixtures.report("MultiConfig")
        let finding = try XCTUnwrap(report.findings(rule: "ASR009").first)
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertEqual(finding.configuration, "Staging")
        XCTAssertTrue(finding.evidence.contains("SWIFT_OPTIMIZATION_LEVEL = -Onone (no optimization)"))
        XCTAssertTrue(finding.evidence.contains("SWIFT_ACTIVE_COMPILATION_CONDITIONS includes DEBUG"))
        XCTAssertFalse(finding.evidence.contains { $0.hasPrefix("Scheme ") }, "Staging is not named Debug")
    }

    func testReleaseConfigurationPasses() throws {
        let report = try Fixtures.report("MultiConfig", configuration: "Release")
        XCTAssertEqual(report.severities(rule: "ASR009"), [.pass])
        XCTAssertEqual(report.findings(rule: "ASR002").first?.evidence, ["CFBundleIdentifier = com.acme.multiconfig"])
    }

    func testDebugConfigurationCanBeInspectedExplicitly() throws {
        let report = try Fixtures.report("MultiConfig", configuration: "Debug")
        let finding = try XCTUnwrap(report.findings(rule: "ASR009").first)
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertFalse(finding.evidence.contains { $0.hasPrefix("Scheme ") }, "user-selected, not a scheme problem")
    }

    func testPrivacyManifestIsManualReviewWhenNotDemonstrablyRequired() throws {
        let report = try Fixtures.report("MultiConfig")
        XCTAssertEqual(report.severities(rule: "ASR007"), [.manualReview])
    }

    // MARK: Engine

    func testDisabledRulesDoNotRun() throws {
        let report = try Fixtures.report("MissingConfig", disabled: ["asr008", "ASR009"])
        XCTAssertEqual(report.findings(rule: "ASR008"), [])
        XCTAssertEqual(report.findings(rule: "ASR009"), [])
        XCTAssertFalse(report.findings(rule: "ASR002").isEmpty)
    }

    func testFindingsFollowRuleOrder() throws {
        let report = try Fixtures.report("MultiTarget")
        let order = RuleRegistry.builtIn.map(\.metadata.id)
        let indices = report.findings.map { order.firstIndex(of: $0.ruleID)! }
        XCTAssertEqual(indices, indices.sorted())
    }
}
