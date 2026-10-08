import XCTest
@testable import AppStoreReadyCore

/// Regression tests for rules ASR011–ASR025 and the phase 2 extensions of
/// ASR006 and ASR007, using the Hardening, PrivacyIssues, and MacApp fixtures.
final class AuditRuleTests: XCTestCase {
    private func titles(_ report: ScanReport, _ rule: String) -> [String] {
        report.findings(rule: rule).map(\.title)
    }

    private func find(_ report: ScanReport, _ rule: String, _ title: String) throws -> Finding {
        try XCTUnwrap(report.findings(rule: rule).first { $0.title == title }, "\(rule): \(title) not reported; got \(titles(report, rule))")
    }

    // MARK: Valid app passes every new rule

    func testValidAppPassesNewRules() throws {
        let report = try Fixtures.report("ValidApp")
        for rule in ["ASR011", "ASR012", "ASR013", "ASR014", "ASR015", "ASR016", "ASR017", "ASR018", "ASR021", "ASR022", "ASR023"] {
            XCTAssertEqual(report.severities(rule: rule), [.pass], rule)
        }
        XCTAssertEqual(report.findings(rule: "ASR019"), [], "no background modes declared")
        XCTAssertEqual(report.findings(rule: "ASR020"), [], "no dependencies")
        XCTAssertEqual(report.findings(rule: "ASR025"), [], "no guideline topics in the code")
        XCTAssertEqual(report.severities(rule: "ASR024"), [.manualReview])
    }

    // MARK: ASR011 Launch screen

    func testMissingLaunchScreenIsVerifiedError() throws {
        let report = try Fixtures.report("Hardening")
        let missing = try find(report, "ASR011", "Missing launch screen")
        XCTAssertEqual(missing.severity, .error)
        XCTAssertEqual(missing.classification, .verifiedIssue)
        XCTAssertEqual(missing.file, "Hardening/Info.plist")
    }

    func testMissingLaunchStoryboardFileIsPotentialIssue() throws {
        let report = try Fixtures.report("MissingConfig")
        let finding = try find(report, "ASR011", "Launch storyboard not found")
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertEqual(finding.classification, .potentialIssue)
    }

    func testLaunchScreenDoesNotApplyToMacApps() throws {
        XCTAssertEqual(try Fixtures.report("MacApp").findings(rule: "ASR011"), [])
    }

    // MARK: ASR012 Deployment target

    func testDeploymentTargetBelowUploadMinimumIsError() throws {
        let finding = try find(try Fixtures.report("Hardening"), "ASR012", "Deployment target below App Store minimum")
        XCTAssertEqual(finding.severity, .error)
        XCTAssertEqual(finding.evidence, ["IPHONEOS_DEPLOYMENT_TARGET = 12.0 (Release)"])
    }

    func testMacDeploymentTargetBelowXcodeRangeIsWarning() throws {
        let finding = try find(try Fixtures.report("MacApp"), "ASR012", "Deployment target below Xcode's supported range")
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertEqual(finding.classification, .potentialIssue)
    }

    func testDeploymentTargetVersionComparison() {
        XCTAssertEqual(DeploymentTargetRule.parse("13.4"), [13, 4])
        XCTAssertNil(DeploymentTargetRule.parse("latest"))
        XCTAssertTrue(DeploymentTargetRule.isLower([12, 4], than: [13]))
        XCTAssertFalse(DeploymentTargetRule.isLower([13], than: [13, 0]))
        XCTAssertFalse(DeploymentTargetRule.isLower([15, 0, 1], than: [15]))
        XCTAssertTrue(DeploymentTargetRule.isLower([14, 9], than: [15]))
    }

    // MARK: ASR013 Export compliance

    func testExportComplianceStates() throws {
        XCTAssertEqual(try Fixtures.report("ValidApp").severities(rule: "ASR013"), [.pass])
        let missing = try Fixtures.report("MultiConfig").findings(rule: "ASR013")
        XCTAssertEqual(missing.map(\.severity), [.info])
        XCTAssertEqual(missing.first?.classification, .bestPractice)
        XCTAssertTrue(missing.first?.message.contains("every upload") ?? false)
        let yes = try find(try Fixtures.report("Hardening"), "ASR013", "App declares non-exempt encryption")
        XCTAssertEqual(yes.severity, .manualReview)
        XCTAssertTrue(yes.evidence.contains("ITSEncryptionExportComplianceCode is not set"))
    }

    // MARK: ASR014 / ASR015 App Transport Security

    func testATSExceptionsAreReported() throws {
        let report = try Fixtures.report("Hardening")
        XCTAssertEqual(Set(titles(report, "ASR014")), [
            "App Transport Security relaxed for web content",
            "App Transport Security allows plain HTTP",
            "App Transport Security allows outdated TLS versions",
        ])
        let http = try find(report, "ASR014", "App Transport Security allows plain HTTP")
        XCTAssertEqual(http.evidence, ["NSExceptionDomains › legacy.acme.com › NSExceptionAllowsInsecureHTTPLoads = YES"], "localhost is not reported")
        XCTAssertTrue(report.findings(rule: "ASR014").allSatisfy { $0.severity == .warning })
    }

    func testInsecureURLsIgnoreHostsWithExceptions() throws {
        let finding = try find(try Fixtures.report("Hardening"), "ASR015", "Insecure HTTP URL in source")
        XCTAssertEqual(finding.evidence, ["Hardening/Network.swift:5 http://reports.acme-analytics.net"])
        XCTAssertEqual(finding.line, 5)
    }

    // MARK: ASR016 Credential files

    func testCredentialFileIsReportedWithoutContents() throws {
        let report = try Fixtures.report("Hardening")
        let finding = try XCTUnwrap(report.findings(rule: "ASR016").first)
        XCTAssertEqual(finding.severity, .warning, "not a target member")
        XCTAssertEqual(finding.file, "Hardening/Certificates/distribution.p12")
        XCTAssertFalse(TextReporter(verbose: true).render(report).contains("not-a-real-certificate"))
    }

    // MARK: ASR017 Signing

    func testSigningProblems() throws {
        XCTAssertEqual(titles(try Fixtures.report("Hardening"), "ASR017"), ["No provisioning profile for manual signing"])
        XCTAssertEqual(titles(try Fixtures.report("MultiConfig"), "ASR017"), ["No development team set"])
    }

    // MARK: ASR018 Entitlements

    func testMalformedEntitlementValues() throws {
        let report = try Fixtures.report("Hardening")
        let invalid = try find(report, "ASR018", "Invalid entitlement value")
        XCTAssertEqual(invalid.severity, .error)
        XCTAssertEqual(invalid.file, "Hardening/Hardening.entitlements")
        XCTAssertEqual(invalid.evidence.count, 3)
        XCTAssertTrue(invalid.evidence[0].contains("'links.acme.com'"))
        XCTAssertFalse(invalid.evidence.contains { $0.contains("applinks:acme.com'") })
    }

    func testHealthKitWithoutUsageStringsIsVerifiedWhenAuthorizationIsRequested() throws {
        let health = try find(try Fixtures.report("Hardening"), "ASR018", "HealthKit enabled without usage descriptions")
        XCTAssertEqual(health.severity, .error)
        XCTAssertEqual(health.file, "Hardening/Health.swift")
        XCTAssertEqual(health.documentationURL?.absoluteString, "https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data")
    }

    func testGetTaskAllowIsPotentialIssue() throws {
        let finding = try find(try Fixtures.report("Hardening"), "ASR018", "Debugging entitlement in archived entitlements")
        XCTAssertEqual(finding.severity, .warning)
        XCTAssertEqual(finding.classification, .potentialIssue)
    }

    func testMacAppWithoutSandbox() throws {
        let finding = try find(try Fixtures.report("MacApp"), "ASR018", "App Sandbox is not enabled")
        XCTAssertEqual(finding.severity, .error)
        XCTAssertEqual(finding.classification, .verifiedIssue)
    }

    func testEntitlementPatterns() {
        for valid in ["applinks:acme.com", "applinks:*.acme.com", "webcredentials:acme.com?mode=developer", "appclips:clip.acme.co.uk", "activitycontinuation:acme.com?mode=developer+managed"] {
            XCTAssertTrue(EntitlementsRule.associatedDomain.matches(valid), valid)
        }
        for invalid in ["acme.com", "links:acme.com", "applinks:https://acme.com", "applinks:acme", "applinks:acme.com?mode=test"] {
            XCTAssertFalse(EntitlementsRule.associatedDomain.matches(invalid), invalid)
        }
        XCTAssertTrue(EntitlementsRule.macAppGroup.matches("ABCDE12345.com.acme.shared"))
        XCTAssertFalse(EntitlementsRule.macAppGroup.matches("com.acme.shared"))
    }

    // MARK: ASR019 Background modes

    func testBackgroundModeProblems() throws {
        let report = try Fixtures.report("Hardening")
        let unpermitted = try find(report, "ASR019", "Background task identifier not permitted")
        XCTAssertEqual(unpermitted.severity, .error)
        XCTAssertEqual(unpermitted.file, "Hardening/Background.swift")
        XCTAssertEqual(unpermitted.line, 5)
        XCTAssertEqual(try find(report, "ASR019", "Unknown background mode").evidence, ["UIBackgroundModes: 'remote-notifications'"])
        XCTAssertEqual(try find(report, "ASR019", "Permitted background task without a handler").severity, .warning)
        let review = try find(report, "ASR019", "Background modes need review (Guideline 2.5.4)")
        XCTAssertEqual(review.severity, .manualReview)
        XCTAssertEqual(review.evidence, ["UIBackgroundModes: processing"])
    }

    // MARK: ASR020 Third-party SDKs

    func testListedSDKsAreMatchedFromLockFilesAndVendoredFrameworks() throws {
        let report = try Fixtures.report("PrivacyIssues")
        let missing = try find(report, "ASR020", "Listed SDK without a privacy manifest")
        XCTAssertEqual(missing.evidence, [
            "FirebaseCore: FirebaseCore 10.0.0 (CocoaPods) has no PrivacyInfo.xcprivacy",
            "Lottie: Frameworks/Lottie.xcframework (vendored binary) has no PrivacyInfo.xcprivacy",
        ])
        let unknown = try find(report, "ASR020", "Listed SDKs need a privacy manifest check")
        XCTAssertEqual(unknown.severity, .manualReview)
        XCTAssertEqual(unknown.evidence, ["Alamofire: Alamofire 5.9.1 (Swift Package Manager)"])
        XCTAssertFalse(report.findings(rule: "ASR020").contains { $0.evidence.contains { $0.contains("SDWebImage") || $0.contains("swift-collections") } })
    }

    func testSDKNameMatching() {
        XCTAssertEqual(ThirdPartySDKRule.listedSDKs.count, 86)
        XCTAssertEqual(ThirdPartySDKRule.listedName(for: "alamofire"), "Alamofire")
        XCTAssertEqual(ThirdPartySDKRule.listedName(for: "firebase-ios-sdk"), "FirebaseCore")
        XCTAssertEqual(ThirdPartySDKRule.listedName(for: "BoringSSL"), "BoringSSL / openssl_grpc")
        XCTAssertNil(ThirdPartySDKRule.listedName(for: "swift-collections"))
    }

    // MARK: ASR021 App icon images

    func testIconImageSizeMismatch() throws {
        let finding = try find(try Fixtures.report("Hardening"), "ASR021", "App icon image has the wrong size")
        XCTAssertEqual(finding.evidence, ["Icon-1024.png is 512x512 pixels; Contents.json expects 1024x1024"])
    }

    func testIconAlphaIsOnlyABestPractice() throws {
        let finding = try find(try Fixtures.report("PrivacyIssues"), "ASR021", "Large app icon has an alpha channel")
        XCTAssertEqual(finding.severity, .info)
        XCTAssertEqual(finding.classification, .bestPractice)
    }

    func testIconScaleIsApplied() throws {
        XCTAssertEqual(try Fixtures.report("MacApp").severities(rule: "ASR021"), [.pass])
        let rule = AppIconImageRule()
        XCTAssertTrue(rule.expectedPixels(size: "83.5x83.5", scale: "2x")! == (167, 167))
        XCTAssertNil(rule.expectedPixels(size: nil, scale: "2x"))
    }

    // MARK: ASR022 / ASR023

    func testReleaseWithoutDSYMIsRecommendation() throws {
        let finding = try XCTUnwrap(try Fixtures.report("Hardening").findings(rule: "ASR022").first)
        XCTAssertEqual(finding.severity, .info)
        XCTAssertEqual(finding.classification, .bestPractice)
    }

    func testAccessibilityHintsNeverClaimCompliance() throws {
        let missing = try XCTUnwrap(try Fixtures.report("MultiConfig").findings(rule: "ASR023").first)
        XCTAssertEqual(missing.severity, .info)
        XCTAssertEqual(missing.confidence, .low)
        let present = try XCTUnwrap(try Fixtures.report("ValidApp").findings(rule: "ASR023").first)
        XCTAssertEqual(present.severity, .pass)
        XCTAssertEqual(present.confidence, .low)
    }

    // MARK: ASR024 App Store metadata

    func testMacCategoryValidation() throws {
        let report = try Fixtures.report("MacApp")
        let finding = try find(report, "ASR024", "Unknown Mac app category")
        XCTAssertEqual(finding.evidence, ["LSApplicationCategoryType = public.app-category.productivity-tools"])
        XCTAssertEqual(AppStoreMetadataRule.categories.count, 40)
        let review = try find(report, "ASR024", "App Store Connect metadata needs review")
        XCTAssertEqual(review.documentationURL?.fragment, "data-collection-and-storage")
    }

    // MARK: ASR025 Guideline topics

    func testGuidelineTopicsAreManualReview() throws {
        let report = try Fixtures.report("Hardening")
        XCTAssertEqual(Set(titles(report, "ASR025")), [
            "In-app purchase rules apply (Guideline 3.1.1)",
            "Third-party sign-in requires an equivalent option (Guideline 4.8)",
            "Account deletion must be offered (Guideline 5.1.1(v))",
            "Build phase scripts were not analyzed",
        ])
        XCTAssertTrue(report.findings(rule: "ASR025").allSatisfy { $0.severity == .manualReview && $0.classification == .manualReview })
        let login = try find(report, "ASR025", "Third-party sign-in requires an equivalent option (Guideline 4.8)")
        XCTAssertEqual(login.documentationURL?.fragment, "login-services")
    }

    func testStoreReviewPromptIsNotAnInAppPurchase() throws {
        XCTAssertEqual(try Fixtures.report("Multiplatform").findings(rule: "ASR025"), [])
        let purchase = GuidelineReviewRule.topics[0].patterns
        XCTAssertFalse(purchase.contains { $0.matches("import StoreKit") })
        XCTAssertFalse(purchase.contains { $0.matches("SKStoreReviewController.requestReview(in: scene)") })
        XCTAssertTrue(purchase.contains { $0.matches("let products = try await Product.products(for: ids)") })
        XCTAssertTrue(purchase.contains { $0.matches("SKPaymentQueue.default().add(payment)") })
    }

    func testCustomLoginManagerIsNotThirdPartySignIn() {
        let login = GuidelineReviewRule.topics[1].patterns
        XCTAssertFalse(login.contains { $0.matches("let manager = LoginManager()") })
        XCTAssertTrue(login.contains { $0.matches("LoginManager().logIn(permissions: [], from: self)") })
        XCTAssertTrue(login.contains { $0.matches("import GoogleSignIn") })
    }

    // MARK: Multiplatform targets

    func testMultiplatformTargetChecksEachPlatform() throws {
        let report = try Fixtures.report("Multiplatform")
        let findings = report.findings(rule: "ASR012")
        XCTAssertEqual(findings.map(\.severity), [.pass, .warning])
        XCTAssertEqual(findings.map { $0.evidence.first ?? "" }, [
            "IPHONEOS_DEPLOYMENT_TARGET = 17.0 (Release)",
            "MACOSX_DEPLOYMENT_TARGET = 10.14 (Release)",
        ])
    }

    // MARK: ASR006 / ASR007 extensions

    func testAlwaysLocationNeedsWhenInUseKey() throws {
        let finding = try find(try Fixtures.report("Hardening"), "ASR006", "Always location access without When In Use description")
        XCTAssertEqual(finding.severity, .error)
        XCTAssertEqual(finding.classification, .verifiedIssue)
    }

    func testPrivacyManifestValuesAreValidated() throws {
        let report = try Fixtures.report("PrivacyIssues")
        let invalid = try find(report, "ASR007", "Invalid required reason declaration")
        XCTAssertEqual(invalid.evidence, [
            "NSPrivacyAccessedAPICategoryFileTimestamp: 'DDA9.2' is not an approved reason for this category",
            "NSPrivacyAccessedAPITypes[2]: 'NSPrivacyAccessedAPICategoryNetwork' is not a documented API category",
        ])
        XCTAssertEqual(try find(report, "ASR007", "SDK-only reason used in an app manifest").evidence, ["NSPrivacyAccessedAPICategoryUserDefaults: C56D.1"])
        XCTAssertEqual(try find(report, "ASR007", "Incomplete collected data entry").severity, .error)
        let values = try find(report, "ASR007", "Undocumented collected data value")
        XCTAssertTrue(values.evidence[0].contains("NSPrivacyCollectedDataTypePhotosOrVideos"), "Apple spells it PhotosorVideos")
        XCTAssertEqual(try find(report, "ASR007", "Tracking domains listed while tracking is off").severity, .warning)
        XCTAssertEqual(try find(report, "ASR007", "Tracking APIs used while the manifest declares no tracking").severity, .manualReview)
        let undeclared = try find(report, "ASR007", "Required reason API not declared")
        XCTAssertTrue(undeclared.message.contains("System boot time"))
    }

    func testRequiredReasonsDoNotApplyToMacOS() throws {
        // MacApp uses @AppStorage (user defaults) and has no manifest: only a manual review item.
        XCTAssertEqual(try Fixtures.report("MacApp").severities(rule: "ASR007"), [.manualReview])
    }

    func testCatalogMatchesAppleLists() {
        XCTAssertEqual(APIUsageCatalog.collectedDataTypes.count, 35)
        XCTAssertEqual(APIUsageCatalog.collectedDataPurposes.count, 6)
        XCTAssertTrue(APIUsageCatalog.collectedDataTypes.contains("NSPrivacyCollectedDataTypePhotosorVideos"))
        let reasons = APIUsageCatalog.requiredReasonCategories.reduce(0) { $0 + $1.reasons.count }
        XCTAssertEqual(reasons, 17)
        for category in APIUsageCatalog.requiredReasonCategories {
            XCTAssertTrue(category.sdkOnlyReasons.isSubset(of: category.reasons), category.identifier)
        }
    }

    // MARK: Cross-cutting

    func testNewFixturesNeverLeakSecretsOrFileContents() throws {
        for fixture in ["Hardening", "PrivacyIssues", "MacApp", "Suppressed"] {
            let report = try Fixtures.report(fixture)
            for output in [TextReporter(verbose: true).render(report), try JSONReporter().render(report)] {
                XCTAssertFalse(output.contains("AKIAIOSFODNN7EXAMPLE"), fixture)
                XCTAssertFalse(output.contains("not-a-real-certificate"), fixture)
            }
        }
    }

    func testHardeningExitCode() throws {
        let report = try Fixtures.report("Hardening")
        XCTAssertEqual(ExitStatus.forReport(report, threshold: .error), .findings)
        XCTAssertGreaterThan(report.summary.manualReview, 0)
    }
}
