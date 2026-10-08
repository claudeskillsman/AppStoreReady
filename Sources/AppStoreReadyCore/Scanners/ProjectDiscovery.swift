import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Errors that prevent a scan from starting.
public enum ScanError: Error, Equatable, CustomStringConvertible {
    case pathNotFound(String)
    case noProjectFound(String)
    case unknownConfiguration(String, available: [String])

    public var description: String {
        switch self {
        case .pathNotFound(let path):
            return "No file or directory exists at '\(path)'."
        case .noProjectFound(let path):
            return "No .xcodeproj or .xcworkspace was found at '\(path)'."
        case .unknownConfiguration(let name, let available):
            let list = available.isEmpty ? "none" : available.joined(separator: ", ")
            return "No build configuration named '\(name)' exists. Available configurations: \(list)."
        }
    }
}

/// Finds the Xcode projects to analyse for a user supplied path.
enum ProjectDiscovery {
    struct Result {
        let root: URL
        let projectURLs: [URL]
        let workspaceURLs: [URL]
    }

    /// Directories never searched for projects or source files.
    static let excludedDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg", ".build", ".swiftpm", "build", "DerivedData",
        "Pods", "Carthage", "node_modules", "SourcePackages", ".bundle", "vendor",
    ]

    static func discover(inputURL: URL) throws -> Result {
        let url = inputURL.standardizedFileURL
        guard PathUtilities.exists(url) else {
            throw ScanError.pathNotFound(inputURL.path)
        }
        switch url.pathExtension {
        case "xcodeproj":
            return Result(root: url.deletingLastPathComponent(), projectURLs: [url], workspaceURLs: [])
        case "xcworkspace":
            let projects = workspaceProjects(url)
            guard !projects.isEmpty else { throw ScanError.noProjectFound(inputURL.path) }
            // Workspaces can reference projects in sibling directories; scan from their common ancestor.
            let root = commonAncestor([url.deletingLastPathComponent()] + projects.map { $0.deletingLastPathComponent() })
            return Result(root: root, projectURLs: projects, workspaceURLs: [url])
        default:
            guard PathUtilities.isDirectory(url) else { throw ScanError.noProjectFound(inputURL.path) }
            var projects = findProjects(in: url, depth: 0)
            var workspaces: [URL] = []
            // Workspaces at the top level can reference projects outside the search depth.
            let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
            for child in children.sorted(by: { $0.path < $1.path }) where child.pathExtension == "xcworkspace" {
                workspaces.append(child)
                for project in workspaceProjects(child) where !projects.contains(project) {
                    projects.append(project)
                }
            }
            guard !projects.isEmpty else { throw ScanError.noProjectFound(inputURL.path) }
            return Result(root: url, projectURLs: projects, workspaceURLs: workspaces)
        }
    }

    static func commonAncestor(_ urls: [URL]) -> URL {
        let paths = urls.map { PathUtilities.standardPath($0).split(separator: "/").map(String.init) }
        guard var common = paths.first else { return URL(fileURLWithPath: "/") }
        for components in paths.dropFirst() {
            var index = 0
            while index < common.count && index < components.count && common[index] == components[index] {
                index += 1
            }
            common = Array(common.prefix(index))
        }
        return URL(fileURLWithPath: "/" + common.joined(separator: "/"))
    }

    private static func findProjects(in directory: URL, depth: Int) -> [URL] {
        guard depth <= 4 else { return [] }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        )) ?? []
        var result: [URL] = []
        for child in children.sorted(by: { $0.path < $1.path }) {
            let name = child.lastPathComponent
            guard !excludedDirectoryNames.contains(name), !PathUtilities.isSymbolicLink(child), PathUtilities.isDirectory(child) else { continue }
            switch child.pathExtension {
            case "xcodeproj":
                result.append(child.standardizedFileURL)
            case "xcworkspace", "xcassets", "app", "framework", "bundle", "lproj":
                continue
            default:
                result += findProjects(in: child, depth: depth + 1)
            }
        }
        return result
    }

    /// Project references from `contents.xcworkspacedata`.
    static func workspaceProjects(_ workspaceURL: URL) -> [URL] {
        let dataURL = workspaceURL.appendingPathComponent("contents.xcworkspacedata")
        guard let data = FileManager.default.contents(atPath: dataURL.path) else { return [] }
        let delegate = WorkspaceDelegate(workspaceDirectory: workspaceURL.deletingLastPathComponent())
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.projects.filter { PathUtilities.isDirectory($0) }
    }

    private final class WorkspaceDelegate: NSObject, XMLParserDelegate {
        let workspaceDirectory: URL
        var groupStack: [URL]
        var projects: [URL] = []

        init(workspaceDirectory: URL) {
            self.workspaceDirectory = workspaceDirectory
            self.groupStack = [workspaceDirectory]
        }

        private func resolve(_ location: String) -> URL? {
            guard let colon = location.firstIndex(of: ":") else { return nil }
            let kind = location[..<colon]
            let path = String(location[location.index(after: colon)...])
            switch kind {
            case "group": return PathUtilities.resolve(path, relativeTo: groupStack.last ?? workspaceDirectory)
            case "container": return PathUtilities.resolve(path, relativeTo: workspaceDirectory)
            case "absolute": return URL(fileURLWithPath: path).standardizedFileURL
            default: return nil
            }
        }

        func parser(
            _ parser: XMLParser,
            didStartElement elementName: String,
            namespaceURI: String?,
            qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            switch elementName {
            case "Group":
                groupStack.append(attributes["location"].flatMap(resolve) ?? (groupStack.last ?? workspaceDirectory))
            case "FileRef":
                if let url = attributes["location"].flatMap(resolve), url.pathExtension == "xcodeproj", !projects.contains(url) {
                    projects.append(url)
                }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
            if elementName == "Group", groupStack.count > 1 {
                groupStack.removeLast()
            }
        }
    }
}
