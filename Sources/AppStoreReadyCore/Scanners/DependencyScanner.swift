import Foundation

/// Reads third-party dependencies from Swift Package Manager, CocoaPods, and
/// Carthage lock files. Lock files are parsed as data; no package manager is run.
enum DependencyScanner {
    static func scan(root: URL, filePaths: [String], issues: inout [ParseIssue]) -> [Dependency] {
        var result: [Dependency] = []
        var seen = Set<String>()
        for relative in filePaths.sorted() {
            let name = (relative as NSString).lastPathComponent
            let url = root.appendingPathComponent(relative)
            var found: [Dependency] = []
            switch name {
            case "Package.resolved":
                found = swiftPackages(url: url, relative: relative, issues: &issues)
            case "Podfile.lock":
                found = pods(url: url, relative: relative, root: root)
            case "Cartfile.resolved":
                found = carthage(url: url, relative: relative)
            default:
                continue
            }
            for dependency in found where seen.insert("\(dependency.manager.rawValue)|\(dependency.name.lowercased())").inserted {
                result.append(dependency)
            }
        }
        return result
    }

    private static func swiftPackages(url: URL, relative: String, issues: inout [ParseIssue]) -> [Dependency] {
        guard
            let data = FileManager.default.contents(atPath: url.path),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            issues.append(ParseIssue(kind: .malformed, relativePath: relative, message: "Package.resolved is not valid JSON."))
            return []
        }
        // Version 1 nests pins under "object"; versions 2 and 3 put them at the top level.
        let pins = (json["pins"] as? [[String: Any]]) ?? ((json["object"] as? [String: Any])?["pins"] as? [[String: Any]]) ?? []
        return pins.compactMap { pin in
            let location = (pin["location"] as? String) ?? (pin["repositoryURL"] as? String) ?? ""
            let identity = (pin["identity"] as? String) ?? (pin["package"] as? String)
            let fromURL = location.split(separator: "/").last.map { String($0).replacingOccurrences(of: ".git", with: "") }
            guard let name = fromURL.flatMap({ $0.isEmpty ? nil : $0 }) ?? identity else { return nil }
            let state = pin["state"] as? [String: Any]
            return Dependency(name: name, version: state?["version"] as? String, manager: .swiftPackageManager, lockFile: relative)
        }
    }

    /// Reads top-level entries of the `PODS:` section, e.g. `  - Alamofire (5.9.1)`.
    private static func pods(url: URL, relative: String, root: URL) -> [Dependency] {
        guard let data = FileManager.default.contents(atPath: url.path) else { return [] }
        let podsDirectory = url.deletingLastPathComponent().appendingPathComponent("Pods")
        let hasPods = PathUtilities.isDirectory(podsDirectory)
        var inPods = false
        var result: [Dependency] = []
        for line in String(decoding: data, as: UTF8.self).components(separatedBy: .newlines) {
            if !line.hasPrefix(" ") && !line.isEmpty {
                inPods = line.hasPrefix("PODS:")
                continue
            }
            guard inPods, line.hasPrefix("  - ") else { continue }
            var entry = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
            if entry.hasPrefix("\"") { entry = entry.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            entry = entry.replacingOccurrences(of: ":", with: "")
            let parts = entry.components(separatedBy: " (")
            let fullName = parts[0].trimmingCharacters(in: .whitespaces)
            let version = parts.count > 1 ? parts[1].replacingOccurrences(of: ")", with: "") : nil
            // Subspecs such as Firebase/Core belong to the pod Firebase.
            let podName = fullName.components(separatedBy: "/")[0]
            var manifest: Bool?
            if hasPods {
                let podDirectory = podsDirectory.appendingPathComponent(podName)
                manifest = PathUtilities.isDirectory(podDirectory) ? containsPrivacyManifest(podDirectory) : nil
            }
            result.append(Dependency(name: podName, version: version, manager: .cocoaPods, lockFile: relative, hasPrivacyManifest: manifest))
        }
        return result
    }

    private static func carthage(url: URL, relative: String) -> [Dependency] {
        guard let data = FileManager.default.contents(atPath: url.path) else { return [] }
        let pattern = TextPattern(#"^\s*(?:github|git|binary)\s+"([^"]+)"\s+"([^"]+)""#)
        return String(decoding: data, as: UTF8.self).components(separatedBy: .newlines).compactMap { line in
            guard let match = pattern.firstMatch(in: line), let source = match[1] else { return nil }
            let name = (source.split(separator: "/").last.map(String.init) ?? source)
                .replacingOccurrences(of: ".git", with: "")
                .replacingOccurrences(of: ".json", with: "")
            return Dependency(name: name, version: match[2], manager: .carthage, lockFile: relative)
        }
    }

    private static func containsPrivacyManifest(_ directory: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return false
        }
        var visited = 0
        while let url = enumerator.nextObject() as? URL {
            visited += 1
            if visited > 20_000 { return false }
            if url.lastPathComponent == "PrivacyInfo.xcprivacy" { return true }
        }
        return false
    }
}
