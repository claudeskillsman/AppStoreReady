import XCTest
@testable import AppStoreReadyCore

final class DependencyAndImageTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("asr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ relative: String, _ contents: String) throws {
        let url = directory.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    func testPackageResolvedVersionOneAndCartfile() throws {
        try write("App.xcworkspace/xcshareddata/swiftpm/Package.resolved", #"""
        {"object": {"pins": [{"package": "Kingfisher", "repositoryURL": "https://github.com/onevcat/Kingfisher.git", "state": {"version": "7.0.0"}}]}, "version": 1}
        """#)
        try write("Cartfile.resolved", "github \"SnapKit/SnapKit\" \"5.7.1\"\nbinary \"https://example.com/sdk.json\" \"1.0\"\n")
        var issues: [ParseIssue] = []
        let dependencies = DependencyScanner.scan(root: directory, filePaths: ["App.xcworkspace/xcshareddata/swiftpm/Package.resolved", "Cartfile.resolved"], issues: &issues)
        XCTAssertEqual(issues, [])
        XCTAssertTrue(dependencies.contains(Dependency(name: "Kingfisher", version: "7.0.0", manager: .swiftPackageManager, lockFile: "App.xcworkspace/xcshareddata/swiftpm/Package.resolved")))
        XCTAssertTrue(dependencies.contains { $0.name == "SnapKit" && $0.manager == .carthage && $0.version == "5.7.1" })
    }

    func testMalformedPackageResolvedIsAParseIssue() throws {
        try write("Package.resolved", "{ not json")
        var issues: [ParseIssue] = []
        XCTAssertEqual(DependencyScanner.scan(root: directory, filePaths: ["Package.resolved"], issues: &issues), [])
        XCTAssertEqual(issues.map(\.kind), [.malformed])
    }

    func testPodfileLockSubspecsAndManifests() throws {
        let report = try Fixtures.scan("PrivacyIssues")
        let pods = report.dependencies.filter { $0.manager == .cocoaPods }
        XCTAssertEqual(pods.map(\.name), ["FirebaseCore", "SDWebImage"], "subspecs collapse into their pod")
        XCTAssertEqual(pods.map(\.hasPrivacyManifest), [false, true])
    }

    func testPNGHeaderIsReadWithoutDecoding() throws {
        let icons = try Fixtures.scan("PrivacyIssues").appIconSets
        let png = try XCTUnwrap(icons.first?.images?.first?.png)
        XCTAssertEqual(png, PNGInfo(width: 1024, height: 1024, hasAlpha: true))
        try write("not-a-png.png", "hello")
        XCTAssertNil(PNGReader.read(directory.appendingPathComponent("not-a-png.png")))
    }
}
