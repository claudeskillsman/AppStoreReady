import XCTest
@testable import AppStoreReadyCore

final class BuildSettingsTests: XCTestCase {
    func testLaterLayersOverrideEarlierOnes() {
        let settings = BuildSettings(layers: [["A": "project"], ["A": "target"]])
        XCTAssertEqual(settings.value("A"), "target")
    }

    func testInheritedPullsFromLowerLayers() {
        let settings = BuildSettings(layers: [
            ["FLAGS": "BASE"],
            ["FLAGS": "$(inherited) PROJECT"],
            ["FLAGS": "TARGET $(inherited)"],
        ])
        XCTAssertEqual(settings.value("FLAGS"), "TARGET BASE PROJECT")
    }

    func testInheritedWithNothingBelowIsEmpty() {
        let settings = BuildSettings(layers: [["SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)"]])
        XCTAssertEqual(settings.value("SWIFT_ACTIVE_COMPILATION_CONDITIONS"), "DEBUG")
    }

    func testExpandsNestedReferencesAndModifiers() {
        let settings = BuildSettings(values: [
            "TARGET_NAME": "My App",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "PRODUCT_BUNDLE_IDENTIFIER": "com.acme.${PRODUCT_NAME:rfc1034identifier}",
            "MODULE": "$(PRODUCT_NAME:c99extidentifier)",
        ])
        XCTAssertEqual(settings.value("PRODUCT_BUNDLE_IDENTIFIER"), "com.acme.My-App")
        XCTAssertEqual(settings.value("MODULE"), "My_App")
        XCTAssertEqual(settings.expand("$(PRODUCT_NAME:lower)"), "my app")
    }

    func testUndefinedVariablesExpandToEmptyAndAreReported() {
        let settings = BuildSettings(values: [:])
        let result = settings.expandTracking("v$(MARKETING_VERSION)")
        XCTAssertEqual(result.value, "v")
        XCTAssertEqual(result.undefined, ["MARKETING_VERSION"])
    }

    func testSelfReferenceDoesNotLoopForever() {
        let settings = BuildSettings(values: ["A": "$(A)x"])
        XCTAssertNotNil(settings.value("A"))
    }

    func testConditionalSettingsAreUsedOnlyWithoutAPlainValue() {
        let settings = BuildSettings(layers: [[
            "CODE_SIGN_IDENTITY[sdk=iphoneos*]": "iPhone Developer",
            "OTHER": "plain",
            "OTHER[sdk=macosx*]": "conditional",
        ]])
        XCTAssertEqual(settings.value("CODE_SIGN_IDENTITY"), "iPhone Developer")
        XCTAssertEqual(settings.value("OTHER"), "plain")
    }

    func testBooleanParsing() {
        let settings = BuildSettings(values: ["A": "YES", "B": "NO", "C": "$(A)"])
        XCTAssertTrue(settings.bool("A"))
        XCTAssertFalse(settings.bool("B"))
        XCTAssertTrue(settings.bool("C"))
        XCTAssertFalse(settings.bool("MISSING"))
    }
}
