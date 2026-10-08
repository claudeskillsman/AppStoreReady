import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads `.xcscheme` files (XML).
enum SchemeParser {
    static func schemes(in containerURL: URL, root: URL, issues: inout [ParseIssue]) -> [Scheme] {
        var result: [Scheme] = []
        let shared = containerURL.appendingPathComponent("xcshareddata/xcschemes")
        result += schemes(inDirectory: shared, isShared: true, root: root, issues: &issues)

        let userData = containerURL.appendingPathComponent("xcuserdata")
        let users = (try? FileManager.default.contentsOfDirectory(at: userData, includingPropertiesForKeys: nil)) ?? []
        for user in users.sorted(by: { $0.path < $1.path }) where user.pathExtension == "xcuserdatad" {
            result += schemes(inDirectory: user.appendingPathComponent("xcschemes"), isShared: false, root: root, issues: &issues)
        }
        return result
    }

    private static func schemes(inDirectory directory: URL, isShared: Bool, root: URL, issues: inout [ParseIssue]) -> [Scheme] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "xcscheme" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                if let scheme = parse(url: url, isShared: isShared) {
                    return scheme
                }
                issues.append(ParseIssue(
                    kind: .malformed,
                    relativePath: PathUtilities.relativePath(of: url, to: root),
                    message: "Scheme file is not valid XML and was ignored."
                ))
                return nil
            }
    }

    static func parse(url: URL, isShared: Bool) -> Scheme? {
        guard let data = FileManager.default.contents(atPath: url.path) else { return nil }
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.sawScheme else { return nil }
        return Scheme(
            name: url.deletingPathExtension().lastPathComponent,
            url: url,
            isShared: isShared,
            archiveConfiguration: delegate.archiveConfiguration,
            launchConfiguration: delegate.launchConfiguration,
            buildableTargetIDs: delegate.targetIDs,
            buildableTargetNames: delegate.targetNames
        )
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var sawScheme = false
        var archiveConfiguration: String?
        var launchConfiguration: String?
        var targetIDs: [String] = []
        var targetNames: [String] = []

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            switch elementName {
            case "Scheme":
                sawScheme = true
            case "ArchiveAction":
                archiveConfiguration = attributes["buildConfiguration"]
            case "LaunchAction":
                launchConfiguration = attributes["buildConfiguration"]
            case "BuildableReference":
                if let id = attributes["BlueprintIdentifier"], !targetIDs.contains(id) {
                    targetIDs.append(id)
                }
                if let name = attributes["BlueprintName"], !targetNames.contains(name) {
                    targetNames.append(name)
                }
            default:
                break
            }
        }
    }
}
