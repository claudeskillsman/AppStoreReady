import Foundation

/// Builds an `XcodeProject` from a `.xcodeproj` bundle.
///
/// Only reads files. Build phases (including "Run Script" phases) are never executed.
enum XcodeProjectLoader {
    static func load(projectURL: URL, root: URL, issues: inout [ParseIssue]) -> XcodeProject? {
        let pbxprojURL = projectURL.appendingPathComponent("project.pbxproj")
        let relative = PathUtilities.relativePath(of: pbxprojURL, to: root)
        guard let data = FileManager.default.contents(atPath: pbxprojURL.path) else {
            issues.append(ParseIssue(kind: .unreadable, relativePath: relative, message: "Project file is missing or unreadable."))
            return nil
        }
        let plist: PlistValue
        do {
            plist = try OpenStepPlistParser.parse(data)
        } catch {
            issues.append(ParseIssue(kind: .malformed, relativePath: relative, message: "Project file could not be parsed (\(error))."))
            return nil
        }
        guard
            let objects = plist["objects"]?.dictionaryValue,
            let rootID = plist["rootObject"]?.stringValue,
            let projectObject = objects[rootID]?.dictionaryValue,
            projectObject["isa"]?.stringValue == "PBXProject"
        else {
            issues.append(ParseIssue(kind: .malformed, relativePath: relative, message: "Project file has no PBXProject root object."))
            return nil
        }

        let graph = ObjectGraph(objects: objects, projectURL: projectURL, projectObject: projectObject)
        var schemeIssues: [ParseIssue] = []
        let schemes = SchemeParser.schemes(in: projectURL, root: root, issues: &schemeIssues)
        issues += schemeIssues

        let (projectConfigurations, projectDefault) = graph.configurations(listID: projectObject["buildConfigurationList"]?.stringValue)
        let targets: [ProjectTarget] = (projectObject["targets"]?.arrayValue ?? []).compactMap { value in
            guard let id = value.stringValue else { return nil }
            return graph.target(id: id)
        }

        return XcodeProject(
            url: projectURL,
            sourceRoot: graph.sourceRoot,
            name: projectURL.deletingPathExtension().lastPathComponent,
            projectConfigurations: projectConfigurations,
            defaultConfigurationName: projectDefault,
            targets: targets,
            schemes: schemes
        )
    }
}

/// Helper for navigating the `objects` dictionary of a pbxproj file.
private final class ObjectGraph {
    let objects: [String: PlistValue]
    let sourceRoot: URL
    private var parents: [String: String] = [:]
    private var pathCache: [String: URL?] = [:]

    init(objects: [String: PlistValue], projectURL: URL, projectObject: [String: PlistValue]) {
        self.objects = objects
        let projectDirPath = projectObject["projectDirPath"]?.stringValue ?? ""
        self.sourceRoot = PathUtilities.resolve(projectDirPath, relativeTo: projectURL.deletingLastPathComponent())
        for (id, object) in objects {
            for child in object["children"]?.arrayValue ?? [] {
                if let childID = child.stringValue {
                    parents[childID] = id
                }
            }
        }
    }

    func object(_ id: String?) -> [String: PlistValue]? {
        guard let id else { return nil }
        return objects[id]?.dictionaryValue
    }

    /// Location on disk of a file reference or group, if it can be determined.
    func path(of id: String) -> URL? {
        if let cached = pathCache[id] { return cached }
        let result = computePath(of: id, depth: 0)
        pathCache[id] = result
        return result
    }

    private func computePath(of id: String, depth: Int) -> URL? {
        guard depth < 64, let object = object(id) else { return nil }
        let path = object["path"]?.stringValue
        switch object["sourceTree"]?.stringValue ?? "<group>" {
        case "<group>":
            let base: URL
            if let parent = parents[id] {
                guard let parentURL = computePath(of: parent, depth: depth + 1) else { return nil }
                base = parentURL
            } else {
                base = sourceRoot
            }
            return path.map { PathUtilities.resolve($0, relativeTo: base) } ?? base
        case "SOURCE_ROOT":
            return PathUtilities.resolve(path ?? "", relativeTo: sourceRoot)
        case "<absolute>":
            return path.map { URL(fileURLWithPath: $0).standardizedFileURL }
        default:
            // BUILT_PRODUCTS_DIR, SDKROOT, DEVELOPER_DIR: not part of the source tree.
            return nil
        }
    }

    func configurations(listID: String?) -> ([RawBuildConfiguration], String?) {
        guard let list = object(listID) else { return ([], nil) }
        let configurations: [RawBuildConfiguration] = (list["buildConfigurations"]?.arrayValue ?? []).compactMap { value in
            guard let configuration = object(value.stringValue), let name = configuration["name"]?.stringValue else { return nil }
            var settings: [String: String] = [:]
            for (key, setting) in configuration["buildSettings"]?.dictionaryValue ?? [:] {
                if let string = setting.stringValue {
                    settings[key] = string
                } else if let array = setting.arrayValue {
                    settings[key] = array.compactMap(\.stringValue).joined(separator: " ")
                }
            }
            var baseFile: URL?
            if let reference = configuration["baseConfigurationReference"]?.stringValue {
                baseFile = path(of: reference)
            } else if
                let anchor = configuration["baseConfigurationReferenceAnchor"]?.stringValue,
                let relativePath = configuration["baseConfigurationReferenceRelativePath"]?.stringValue,
                let anchorURL = path(of: anchor) {
                baseFile = PathUtilities.resolve(relativePath, relativeTo: anchorURL)
            }
            return RawBuildConfiguration(name: name, settings: settings, baseConfigurationFile: baseFile)
        }
        return (configurations, list["defaultConfigurationName"]?.stringValue)
    }

    func target(id: String) -> ProjectTarget? {
        guard
            let target = object(id),
            target["isa"]?.stringValue == "PBXNativeTarget",
            let name = target["name"]?.stringValue
        else { return nil }

        var files = Set<String>()
        var directories: [String] = []
        var excluded = Set<String>()
        var scripts: [String] = []

        func addMember(_ url: URL) {
            if PathUtilities.isDirectory(url) {
                directories.append(PathUtilities.standardPath(url))
            } else {
                files.insert(PathUtilities.standardPath(url))
            }
        }

        for phaseValue in target["buildPhases"]?.arrayValue ?? [] {
            guard let phase = object(phaseValue.stringValue) else { continue }
            let isa = phase["isa"]?.stringValue
            if isa == "PBXShellScriptBuildPhase" {
                scripts.append(phase["name"]?.stringValue ?? "Run Script")
                continue
            }
            guard isa == "PBXSourcesBuildPhase" || isa == "PBXResourcesBuildPhase" else { continue }
            for buildFileValue in phase["files"]?.arrayValue ?? [] {
                guard let buildFile = object(buildFileValue.stringValue), let reference = buildFile["fileRef"]?.stringValue else { continue }
                let referenced = object(reference)
                if referenced?["isa"]?.stringValue == "PBXVariantGroup" {
                    for child in referenced?["children"]?.arrayValue ?? [] {
                        if let childID = child.stringValue, let url = path(of: childID) { addMember(url) }
                    }
                } else if let url = path(of: reference) {
                    addMember(url)
                }
            }
        }

        for groupValue in target["fileSystemSynchronizedGroups"]?.arrayValue ?? [] {
            guard let groupID = groupValue.stringValue, let groupURL = path(of: groupID) else { continue }
            directories.append(PathUtilities.standardPath(groupURL))
            for exceptionValue in object(groupID)?["exceptions"]?.arrayValue ?? [] {
                guard let exception = object(exceptionValue.stringValue), exception["target"]?.stringValue == id else { continue }
                for relative in exception["membershipExceptions"]?.arrayValue ?? [] {
                    if let relativePath = relative.stringValue {
                        excluded.insert(PathUtilities.standardPath(groupURL.appendingPathComponent(relativePath)))
                    }
                }
            }
        }

        let (configurations, defaultName) = configurations(listID: target["buildConfigurationList"]?.stringValue)
        return ProjectTarget(
            id: id,
            name: name,
            productType: ProductType(identifier: target["productType"]?.stringValue ?? ""),
            configurations: configurations,
            defaultConfigurationName: defaultName,
            memberFiles: files,
            memberDirectories: directories,
            excludedFiles: excluded,
            scriptPhaseNames: scripts
        )
    }
}
