import XCTest

/// Guards the security model: the tool reads files and nothing else.
final class SecurityModelTests: XCTestCase {
    private static let sourcesRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources")

    private func sourceFiles() throws -> [(String, String)] {
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.sourcesRoot, includingPropertiesForKeys: nil))
        var result: [(String, String)] = []
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            result.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return result
    }

    func testSourcesDoNotExecuteProcessesOrUseTheNetwork() throws {
        let forbidden = ["Process(", "NSTask", "posix_spawn", "system(", "popen(", "URLSession", "URLRequest", "NWConnection", "CFNetwork", "Data(contentsOf: URL(string"]
        let files = try sourceFiles()
        XCTAssertGreaterThan(files.count, 20)
        for (name, contents) in files {
            for token in forbidden {
                XCTAssertFalse(contents.contains(token), "\(name) contains forbidden API \(token)")
            }
        }
    }

    func testCoreDoesNotImportPlatformSpecificUIFrameworks() throws {
        for (name, contents) in try sourceFiles() {
            for framework in ["import AppKit", "import UIKit", "import SwiftUI", "import Combine"] {
                XCTAssertFalse(contents.contains(framework), "\(name) imports \(framework)")
            }
        }
    }
}
