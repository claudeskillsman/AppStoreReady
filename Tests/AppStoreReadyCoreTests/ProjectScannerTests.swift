import XCTest
@testable import AppStoreReadyCore

final class ProjectScannerTests: XCTestCase {
    func testDirectoryInputFindsProject() throws {
        let context = try Fixtures.scan("ValidApp")
        XCTAssertEqual(context.projects.map(\.name), ["ValidApp"])
        XCTAssertEqual(context.rootURL.lastPathComponent, "ValidApp")
    }

    func testProjectBundleInputUsesParentAsRoot() throws {
        let context = try Fixtures.scan("ValidApp/ValidApp.xcodeproj")
        XCTAssertEqual(context.projects.count, 1)
        XCTAssertEqual(context.rootURL.lastPathComponent, "ValidApp")
        XCTAssertFalse(context.files.isEmpty)
    }

    func testWorkspaceInputResolvesReferencedProjectsAndSchemes() throws {
        let context = try Fixtures.scan("WorkspaceApp/WorkspaceApp.xcworkspace")
        XCTAssertEqual(context.projects.map(\.name), ["App"])
        let target = try XCTUnwrap(context.target(named: "App"))
        XCTAssertEqual(target.configurationSource, .schemeArchive(scheme: "App"))
        XCTAssertEqual(target.infoPlist?.string("CFBundleIdentifier"), "com.acme.workspaceapp")
    }

    func testMissingPathThrows() {
        XCTAssertThrowsError(try Fixtures.scan("DoesNotExist")) { error in
            guard case ScanError.pathNotFound = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testDirectoryWithoutProjectThrows() {
        XCTAssertThrowsError(try Fixtures.scan("NoProject")) { error in
            guard case ScanError.noProjectFound = error else { return XCTFail("unexpected \(error)") }
        }
    }

    func testUnknownConfigurationThrows() {
        XCTAssertThrowsError(try Fixtures.scan("MultiConfig", configuration: "Production")) { error in
            XCTAssertEqual(error as? ScanError, .unknownConfiguration("Production", available: ["Debug", "Release", "Staging"]))
        }
    }

    func testGeneratedInfoPlistResolvesBuildSettings() throws {
        let context = try Fixtures.scan("ValidApp")
        let target = try XCTUnwrap(context.target(named: "ValidApp"))
        let info = try XCTUnwrap(target.infoPlist)
        XCTAssertTrue(info.isGenerated)
        XCTAssertNil(info.url)
        XCTAssertEqual(info.string("CFBundleIdentifier"), "com.acme.validapp")
        XCTAssertEqual(info.string("CFBundleShortVersionString"), "1.2.0")
        XCTAssertEqual(info.string("CFBundleVersion"), "42")
        XCTAssertEqual(info.string("CFBundleExecutable"), "ValidApp")
        XCTAssertNotNil(info.string("NSLocationWhenInUseUsageDescription"))
    }

    func testOnlyDistributableTargetsAreResolved() throws {
        let valid = try Fixtures.scan("ValidApp")
        XCTAssertEqual(valid.targets.map(\.name), ["ValidApp"], "UI test bundles are not distributed")
        XCTAssertEqual(valid.projects[0].targets.count, 2)

        let multi = try Fixtures.scan("MultiTarget")
        XCTAssertEqual(Set(multi.targets.map(\.name)), ["Shop", "ShopWidget"])
        XCTAssertEqual(multi.target(named: "ShopWidget")?.productType, .appExtension)
        let all = multi.projects[0].targets
        XCTAssertEqual(all.first { $0.name == "ShopKit" }?.productType, .framework)
        XCTAssertEqual(all.first { $0.name == "ShopTests" }?.productType, .unitTest)
    }

    func testTargetMembershipFromBuildPhases() throws {
        let context = try Fixtures.scan("ValidApp")
        let target = try XCTUnwrap(context.target(named: "ValidApp"))
        let (files, exact) = context.codeFiles(for: target)
        XCTAssertTrue(exact)
        XCTAssertEqual(Set(files.map(\.relativePath)), ["ValidApp/ValidAppApp.swift", "ValidApp/StoreLocator.swift"])
        XCTAssertEqual(context.privacyManifests.filter { target.target.contains(path: $0.path) }.count, 1)
    }

    func testSynchronizedGroupMembershipHonorsExceptions() throws {
        let context = try Fixtures.scan("MultiTarget")
        let widget = try XCTUnwrap(context.target(named: "ShopWidget"))
        let files = context.codeFiles(for: widget).files.map(\.relativePath)
        XCTAssertEqual(files, ["ShopWidget/ShopWidget.swift"])
        XCTAssertFalse(files.contains("ShopWidget/Preview/PreviewLocation.swift"))
    }

    func testProjectLevelSettingsAreInheritedAndTargetOverrides() throws {
        let context = try Fixtures.scan("MultiTarget")
        XCTAssertEqual(context.target(named: "Shop")?.infoPlist?.string("CFBundleShortVersionString"), "2.0.0")
        XCTAssertEqual(context.target(named: "ShopWidget")?.infoPlist?.string("CFBundleShortVersionString"), "1.9.0")
        XCTAssertEqual(context.target(named: "ShopWidget")?.infoPlist?.string("CFBundleVersion"), "7")
    }

    func testSchemeArchiveConfigurationIsSelectedByDefault() throws {
        let context = try Fixtures.scan("MultiConfig")
        let target = try XCTUnwrap(context.target(named: "MultiConfig"))
        XCTAssertEqual(target.configurationName, "Staging")
        XCTAssertEqual(target.configurationSource, .schemeArchive(scheme: "MultiConfig"))
        XCTAssertEqual(Set(target.allConfigurations.keys), ["Debug", "Staging", "Release"])
    }

    func testXCConfigFilesAndIncludesAreApplied() throws {
        let staging = try XCTUnwrap(Fixtures.scan("MultiConfig").target(named: "MultiConfig"))
        XCTAssertEqual(staging.infoPlist?.string("CFBundleIdentifier"), "com.acme.multiconfig.staging")
        XCTAssertEqual(staging.infoPlist?.string("CFBundleShortVersionString"), "3.1.0", "from the included Shared.xcconfig")
        XCTAssertEqual(staging.infoPlist?.string("CFBundleVersion"), "101")

        let release = try XCTUnwrap(Fixtures.scan("MultiConfig", configuration: "Release").target(named: "MultiConfig"))
        XCTAssertEqual(release.configurationSource, .userSpecified)
        XCTAssertEqual(release.infoPlist?.string("CFBundleIdentifier"), "com.acme.multiconfig")
        XCTAssertEqual(release.infoPlist?.string("CFBundleVersion"), "102")
        XCTAssertEqual(release.allConfigurations["Debug"]?.value("CURRENT_PROJECT_VERSION"), "100")
    }

    func testReleaseIsAssumedWithoutAScheme() throws {
        let context = try Fixtures.scan("MultiTarget")
        XCTAssertEqual(context.target(named: "Shop")?.configurationSource, .schemeArchive(scheme: "Shop"))
        XCTAssertEqual(context.target(named: "ShopWidget")?.configurationSource, .releaseByName)
    }

    func testMalformedFilesBecomeParseIssues() throws {
        let context = try Fixtures.scan("Malformed")
        let paths = Set(context.parseIssues.map(\.relativePath))
        XCTAssertTrue(paths.contains("Malformed/Info.plist"))
        XCTAssertTrue(paths.contains("Malformed/PrivacyInfo.xcprivacy"))
        XCTAssertTrue(paths.contains("Malformed/Assets.xcassets/AppIcon.appiconset/Contents.json"))
        XCTAssertEqual(context.target(named: "Malformed")?.infoPlist?.isUnreadable, true)
        XCTAssertNil(context.privacyManifests.first?.contents)
    }

    func testBrokenProjectFileIsReportedNotThrown() throws {
        let context = try Fixtures.scan("BrokenProject")
        XCTAssertTrue(context.projects.isEmpty)
        XCTAssertEqual(context.parseIssues.map(\.kind), [.malformed])
        XCTAssertEqual(context.parseIssues.first?.relativePath, "BrokenProject.xcodeproj/project.pbxproj")
    }

    func testAppIconSetsAreDiscovered() throws {
        let context = try Fixtures.scan("ValidApp")
        let icon = try XCTUnwrap(context.appIconSets.first)
        XCTAssertEqual(icon.name, "AppIcon")
        XCTAssertEqual(icon.images?.first?.size, "1024x1024")
        XCTAssertEqual(icon.images?.first?.fileExists, true)
    }

    func testPrivacyManifestValuesKeepTheirTypes() throws {
        let manifest = try XCTUnwrap(Fixtures.scan("ValidApp").privacyManifests.first)
        XCTAssertEqual(manifest.contents?["NSPrivacyTracking"], .bool(false))
        XCTAssertEqual(manifest.declaredAPICategories, ["NSPrivacyAccessedAPICategoryUserDefaults": ["CA92.1"]])
    }

    func testCommonAncestor() {
        let ancestor = ProjectDiscovery.commonAncestor([
            URL(fileURLWithPath: "/a/b/c"),
            URL(fileURLWithPath: "/a/b/d/e"),
        ])
        XCTAssertEqual(ancestor.path, "/a/b")
    }
}
