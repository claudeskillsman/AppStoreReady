import XCTest
@testable import AppStoreReadyCore

final class OpenStepPlistParserTests: XCTestCase {
    func testParsesNestedStructuresAndComments() throws {
        let source = """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            /* a block comment */
            objects = {
                ABC123 /* Thing */ = {isa = PBXFileReference; path = "My File.swift"; sourceTree = "<group>"; };
            };
            list = (one, "two words", three, );
            empty = ();
            data = <0aff>;
        }
        """
        let value = try OpenStepPlistParser.parse(Data(source.utf8))
        XCTAssertEqual(value["archiveVersion"]?.stringValue, "1")
        XCTAssertEqual(value["objects"]?["ABC123"]?["path"]?.stringValue, "My File.swift")
        XCTAssertEqual(value["objects"]?["ABC123"]?["sourceTree"]?.stringValue, "<group>")
        XCTAssertEqual(value["list"]?.arrayValue?.compactMap(\.stringValue), ["one", "two words", "three"])
        XCTAssertEqual(value["empty"]?.arrayValue?.count, 0)
        XCTAssertEqual(value["data"], .data(Data([0x0a, 0xff])))
    }

    func testDecodesEscapes() throws {
        let value = try OpenStepPlistParser.parse(Data(#"{ a = "line\nnext \"quoted\" back\\slash"; }"#.utf8))
        XCTAssertEqual(value["a"]?.stringValue, "line\nnext \"quoted\" back\\slash")
    }

    func testReportsLineOfSyntaxError() {
        let source = "{\n  a = 1;\n  b = 2\n}\n"
        XCTAssertThrowsError(try OpenStepPlistParser.parse(Data(source.utf8))) { error in
            let parseError = error as? OpenStepPlistParser.ParseError
            XCTAssertNotNil(parseError)
            XCTAssertEqual(parseError?.line, 4)
        }
    }

    func testRejectsTruncatedInput() {
        XCTAssertThrowsError(try OpenStepPlistParser.parse(Data("{ objects = { a = (1, 2".utf8)))
        XCTAssertThrowsError(try OpenStepPlistParser.parse(Data(#"{ a = "unterminated; }"#.utf8)))
        XCTAssertThrowsError(try OpenStepPlistParser.parse(Data("{ a = 1; } extra".utf8)))
    }

    func testParsesEveryFixtureProjectExceptTheBrokenOne() throws {
        let fixtures = ["ValidApp/ValidApp", "MissingConfig/MissingConfig", "Malformed/Malformed", "MultiTarget/MultiTarget", "MultiConfig/MultiConfig", "WorkspaceApp/App/App"]
        for fixture in fixtures {
            let url = Fixtures.root.appendingPathComponent("\(fixture).xcodeproj/project.pbxproj")
            let data = try XCTUnwrap(FileManager.default.contents(atPath: url.path), fixture)
            XCTAssertNoThrow(try OpenStepPlistParser.parse(data), fixture)
        }
        let broken = Fixtures.root.appendingPathComponent("BrokenProject/BrokenProject.xcodeproj/project.pbxproj")
        XCTAssertThrowsError(try OpenStepPlistParser.parse(try XCTUnwrap(FileManager.default.contents(atPath: broken.path))))
    }
}
