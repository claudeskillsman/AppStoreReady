import Foundation

/// Walks the scan root and loads the text files that rules inspect.
///
/// Symbolic links are never followed, binary files are skipped, and
/// file sizes and counts are capped so a scan cannot run away on large trees.
struct FileCollector {
    struct Output {
        var files: [SourceFile] = []
        var privacyManifests: [PrivacyManifest] = []
        var appIconSets: [AppIconSet] = []
        var issues: [ParseIssue] = []
    }

    let root: URL
    let maxFileSize: Int
    let maxFileCount: Int

    static let textExtensions: [String: SourceFile.Kind] = [
        "swift": .swift,
        "m": .objectiveC, "mm": .objectiveC, "c": .objectiveC, "cpp": .objectiveC,
        "h": .header, "hpp": .header,
        "plist": .plist, "xcprivacy": .plist, "entitlements": .plist,
        "json": .json,
        "xcconfig": .xcconfig,
        "strings": .strings,
        "sh": .script, "rb": .script, "py": .script, "js": .script, "ts": .script,
        "xcscheme": .other, "pbxproj": .other, "yml": .other, "yaml": .other,
        "properties": .other, "env": .environment,
    ]

    func collect() -> Output {
        var output = Output()
        walk(root, output: &output, depth: 0)
        output.files.sort { $0.relativePath < $1.relativePath }
        output.privacyManifests.sort { $0.relativePath < $1.relativePath }
        output.appIconSets.sort { $0.relativePath < $1.relativePath }
        return output
    }

    private func walk(_ directory: URL, output: inout Output, depth: Int) {
        guard depth < 24 else { return }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        )) ?? []
        for child in children.sorted(by: { $0.path < $1.path }) {
            if output.files.count >= maxFileCount { return }
            let name = child.lastPathComponent
            if PathUtilities.isSymbolicLink(child) { continue }
            if PathUtilities.isDirectory(child) {
                if ProjectDiscovery.excludedDirectoryNames.contains(name) { continue }
                if child.pathExtension == "xcassets" {
                    collectAssetCatalog(child, output: &output)
                    continue
                }
                walk(child, output: &output, depth: depth + 1)
                continue
            }
            let kind: SourceFile.Kind?
            if name == ".env" || name.hasPrefix(".env.") {
                kind = .environment
            } else {
                kind = FileCollector.textExtensions[child.pathExtension.lowercased()]
            }
            guard let kind else { continue }
            load(child, kind: kind, output: &output)
        }
    }

    private func load(_ url: URL, kind: SourceFile.Kind, output: inout Output) {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maxFileSize, let data = FileManager.default.contents(atPath: url.path) else { return }
        let path = PathUtilities.standardPath(url)
        let relative = PathUtilities.relativePath(of: url, to: root)

        if url.pathExtension == "xcprivacy" {
            let parsed = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil))
                .flatMap(PlistValue.init(foundation:))?
                .dictionaryValue
            output.privacyManifests.append(PrivacyManifest(url: url, path: path, relativePath: relative, contents: parsed))
            if parsed == nil {
                output.issues.append(ParseIssue(kind: .malformed, relativePath: relative, message: "Privacy manifest is not a valid property list."))
            }
        }

        // Binary property lists and other binary files are not scanned as text.
        if data.prefix(8192).contains(0) { return }
        let contents = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        output.files.append(SourceFile(url: url, path: path, relativePath: relative, kind: kind, contents: contents))
    }

    private func collectAssetCatalog(_ catalog: URL, output: inout Output) {
        guard let enumerator = FileManager.default.enumerator(
            at: catalog,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "appiconset" else { continue }
            let relative = PathUtilities.relativePath(of: url, to: root)
            let contentsURL = url.appendingPathComponent("Contents.json")
            var images: [AppIconSet.Image]?
            if let data = FileManager.default.contents(atPath: contentsURL.path) {
                if
                    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let entries = json["images"] as? [[String: Any]] {
                    images = entries.map { entry in
                        let filename = entry["filename"] as? String
                        return AppIconSet.Image(
                            filename: filename,
                            size: entry["size"] as? String,
                            idiom: entry["idiom"] as? String,
                            fileExists: filename.map { PathUtilities.exists(url.appendingPathComponent($0)) } ?? false
                        )
                    }
                } else {
                    output.issues.append(ParseIssue(
                        kind: .malformed,
                        relativePath: PathUtilities.relativePath(of: contentsURL, to: root),
                        message: "App icon set Contents.json is not valid JSON."
                    ))
                }
            }
            output.appIconSets.append(AppIconSet(
                name: url.deletingPathExtension().lastPathComponent,
                url: url,
                path: PathUtilities.standardPath(url),
                relativePath: relative,
                images: images
            ))
        }
    }
}
