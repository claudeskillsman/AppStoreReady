import XCTest
@testable import AppStoreReadyCore

final class HardcodedSecretRuleTests: XCTestCase {
    private let rule = HardcodedSecretRule()

    // Values are assembled at runtime so this test file does not itself look like a leak.
    private let githubToken = "ghp_" + String(repeating: "aB3dE5fG7h", count: 4)
    private let stripeKey = "sk_" + "live_" + "4eC39HqLyjWDarjtT1zdp7dc"
    private let slackToken = "xoxb-" + "1234567890-abcdefghij"
    private let googleKey = "AIza" + "SyD-9tSrke72PouQMnMX-a7eZSW0jkFMBWY"

    private func kinds(_ findings: [Finding]) -> [String] {
        findings.compactMap { $0.evidence.first?.components(separatedBy: ",").first }
    }

    func testDetectsProviderTokens() {
        let file = makeSourceFile("App/Keys.swift", """
        let github = "\(githubToken)"
        let stripe = "\(stripeKey)"
        let slack = "\(slackToken)"
        """)
        let findings = rule.scan(file)
        XCTAssertEqual(kinds(findings), ["GitHub token", "Stripe live secret key", "Slack token"])
        XCTAssertEqual(findings.map(\.line), [1, 2, 3])
        XCTAssertTrue(findings.allSatisfy { $0.severity == .error && $0.confidence == .high })
    }

    func testDetectsPrivateKeyBlocks() {
        let file = makeSourceFile("App/key.pem.swift", "let pem = \"\"\"\n-----BEGIN " + "RSA PRIVATE KEY-----\nMIIE...\n\"\"\"")
        XCTAssertEqual(kinds(rule.scan(file)), ["Private key"])
    }

    func testGoogleKeyIsAWarningAndSkippedInGoogleServiceInfo() {
        let swift = makeSourceFile("App/Maps.swift", "let key = \"\(googleKey)\"")
        XCTAssertEqual(rule.scan(swift).map(\.severity), [.warning])
        let plist = makeSourceFile("App/GoogleService-Info.plist", "<key>API_KEY</key>\n<string>\(googleKey)</string>", kind: .plist)
        let findings = rule.scan(plist)
        XCTAssertFalse(kinds(findings).contains("Google API key"))
    }

    func testGenericAssignmentsUseEntropyAndPlaceholderFilters() {
        let file = makeSourceFile("App/Config.swift", """
        let apiKey = "Zx81QmPq07LkWr4Tn2Bv"
        let apiKeyPlaceholder = "YOUR_API_KEY_HERE"
        let password = "aaaaaaaaaaaaaaaa"
        static let authTokenKey = "com.acme.authTokenKey"
        let clientSecret: String = "$(CLIENT_SECRET)"
        """)
        let findings = rule.scan(file)
        XCTAssertEqual(findings.map(\.line), [1])
        XCTAssertEqual(findings.first?.severity, .warning)
    }

    func testPlistKeyValuePairs() {
        let file = makeSourceFile("App/Config.plist", """
        <dict>
            <key>ServerAPIKey</key>
            <string>c29tZS1yZWFsLWxvb2tpbmctdmFsdWU9</string>
            <key>NSCameraUsageDescription</key>
            <string>Scanning receipts</string>
        </dict>
        """, kind: .plist)
        let findings = rule.scan(file)
        XCTAssertEqual(findings.map(\.line), [3])
    }

    func testXcconfigAndEnvironmentFiles() {
        let xcconfig = makeSourceFile("Config/Secrets.xcconfig", "ANALYTICS_API_KEY = 9fK2mQ7xL4pR8sT1vW3y\nOTHER = $(ANALYTICS_API_KEY)\n", kind: .xcconfig)
        XCTAssertEqual(rule.scan(xcconfig).map(\.line), [1])
        let env = makeSourceFile(".env", "STRIPE_SECRET=Hk4Lm9Np2Qr7St1Uv6Wx\n", kind: .environment)
        XCTAssertEqual(rule.scan(env).map(\.line), [1])
    }

    func testSuppressionMarker() {
        let file = makeSourceFile("App/Keys.swift", "let github = \"\(githubToken)\" // appstoreready:ignore")
        XCTAssertEqual(rule.scan(file), [])
    }

    func testOneFindingPerLine() {
        let file = makeSourceFile("App/Keys.swift", "let apiKey = \"\(githubToken)\"")
        let findings = rule.scan(file)
        XCTAssertEqual(findings.count, 1)
        XCTAssertEqual(kinds(findings), ["GitHub token"])
    }

    func testFindingsNeverContainTheSecret() throws {
        let secrets = [githubToken, stripeKey, slackToken, "Zx81QmPq07LkWr4Tn2Bv"]
        let file = makeSourceFile("App/Keys.swift", """
        let github = "\(githubToken)"
        let stripe = "\(stripeKey)"
        let slack = "\(slackToken)"
        let apiKey = "Zx81QmPq07LkWr4Tn2Bv"
        """)
        let findings = rule.scan(file)
        XCTAssertEqual(findings.count, 4)
        let report = ScanReport(scannedPath: "x", projects: [], targets: [], findings: findings)
        let outputs = [
            try JSONReporter().render(report),
            TextReporter(useColor: false, verbose: true).render(report),
            TextReporter(useColor: true, verbose: false).render(report),
        ]
        for output in outputs {
            for secret in secrets {
                XCTAssertFalse(output.contains(secret), "secret leaked into output")
                XCTAssertFalse(output.contains(String(secret.suffix(8))), "partial secret leaked into output")
            }
        }
        XCTAssertTrue(findings[0].evidence[0].contains("[REDACTED: \(githubToken.count) characters]"))
    }

    func testFixtureSecretNeverAppearsInReports() throws {
        let report = try Fixtures.report("MissingConfig")
        let json = try JSONReporter().render(report)
        let text = TextReporter(verbose: true).render(report)
        for value in ["AKIAIOSFODNN7EXAMPLE", "q8Zt3vN1pLx7Rk2Wm9Yc"] {
            XCTAssertFalse(json.contains(value))
            XCTAssertFalse(text.contains(value))
        }
    }

    func testEntropy() {
        XCTAssertEqual(Redactor.entropy("aaaa"), 0)
        XCTAssertEqual(Redactor.entropy("abcd"), 2, accuracy: 0.0001)
        XCTAssertGreaterThan(Redactor.entropy("Zx81QmPq07LkWr4Tn2Bv"), 3.5)
    }
}
