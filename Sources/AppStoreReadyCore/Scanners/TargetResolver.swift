import Foundation

/// Resolves build settings and the effective Info.plist of distributable targets.
struct TargetResolver {
    let root: URL
    let requestedConfiguration: String?
    let workspaceSchemes: [Scheme]
    private var xcconfigCache: [String: [String: String]] = [:]

    init(root: URL, requestedConfiguration: String?, workspaceSchemes: [Scheme]) {
        self.root = root
        self.requestedConfiguration = requestedConfiguration
        self.workspaceSchemes = workspaceSchemes
    }

    mutating func resolve(project: XcodeProject, issues: inout [ParseIssue]) -> [ResolvedTarget] {
        project.targets.filter(\.productType.isDistributableBundle).compactMap { target in
            resolve(target: target, project: project, issues: &issues)
        }
    }

    private mutating func resolve(target: ProjectTarget, project: XcodeProject, issues: inout [ParseIssue]) -> ResolvedTarget? {
        let names = target.configurations.map(\.name)
        guard !names.isEmpty else {
            issues.append(ParseIssue(
                kind: .malformed,
                relativePath: PathUtilities.relativePath(of: project.url, to: root),
                message: "Target '\(target.name)' has no build configurations."
            ))
            return nil
        }
        guard let (configurationName, source) = chooseConfiguration(for: target, in: project) else {
            return nil
        }

        var all: [String: BuildSettings] = [:]
        for name in names {
            all[name] = settings(for: target, in: project, configuration: name, issues: &issues)
        }
        guard let settings = all[configurationName] else { return nil }

        return ResolvedTarget(
            target: target,
            project: project,
            configurationName: configurationName,
            configurationSource: source,
            buildSettings: settings,
            allConfigurations: all,
            infoPlist: infoPlist(settings: settings, project: project, issues: &issues),
            entitlements: entitlements(settings: settings, project: project, issues: &issues)
        )
    }

    private func chooseConfiguration(for target: ProjectTarget, in project: XcodeProject) -> (String, ConfigurationSource)? {
        let names = target.configurations.map(\.name)
        if let requested = requestedConfiguration {
            return names.contains(requested) ? (requested, .userSpecified) : nil
        }
        let candidates = (project.schemes + workspaceSchemes).filter {
            $0.archiveConfiguration != nil && $0.buildableTargetIDs.contains(target.id)
        }
        // Prefer a shared scheme named after the target, then any shared scheme, then user schemes.
        let ordered = candidates.sorted { lhs, rhs in
            func score(_ scheme: Scheme) -> Int {
                (scheme.isShared ? 0 : 2) + (scheme.name == target.name ? 0 : 1)
            }
            return score(lhs) < score(rhs)
        }
        if let scheme = ordered.first, let archive = scheme.archiveConfiguration, names.contains(archive) {
            return (archive, .schemeArchive(scheme: scheme.name))
        }
        if names.contains("Release") {
            return ("Release", .releaseByName)
        }
        let fallback = target.defaultConfigurationName ?? project.defaultConfigurationName ?? names[0]
        return (names.contains(fallback) ? fallback : names[0], .projectDefault)
    }

    private mutating func settings(for target: ProjectTarget, in project: XcodeProject, configuration: String, issues: inout [ParseIssue]) -> BuildSettings {
        let projectConfiguration = project.projectConfigurations.first { $0.name == configuration }
        let targetConfiguration = target.configurations.first { $0.name == configuration }
        let defaults: [String: String] = [
            "TARGET_NAME": target.name,
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "PROJECT_NAME": project.name,
            "SRCROOT": project.sourceRoot.path,
            "SOURCE_ROOT": project.sourceRoot.path,
            "PROJECT_DIR": project.sourceRoot.path,
            "CONFIGURATION": configuration,
            "EXECUTABLE_NAME": "$(PRODUCT_NAME)",
            "PRODUCT_MODULE_NAME": "$(PRODUCT_NAME:c99extidentifier)",
            "DEVELOPMENT_LANGUAGE": "en",
        ]
        return BuildSettings(layers: [
            defaults,
            xcconfig(projectConfiguration?.baseConfigurationFile, issues: &issues),
            projectConfiguration?.settings ?? [:],
            xcconfig(targetConfiguration?.baseConfigurationFile, issues: &issues),
            targetConfiguration?.settings ?? [:],
        ])
    }

    private mutating func xcconfig(_ url: URL?, issues: inout [ParseIssue]) -> [String: String] {
        guard let url else { return [:] }
        let key = url.path
        if let cached = xcconfigCache[key] { return cached }
        var newIssues: [ParseIssue] = []
        let parsed = XCConfigParser.parse(url: url, root: root, issues: &newIssues)
        for issue in newIssues where !issues.contains(issue) {
            issues.append(issue)
        }
        xcconfigCache[key] = parsed
        return parsed
    }

    private func infoPlist(settings: BuildSettings, project: XcodeProject, issues: inout [ParseIssue]) -> InfoPlist? {
        var raw: [String: PlistValue] = [:]
        let generated = settings.bool("GENERATE_INFOPLIST_FILE")
        if generated {
            // Keys Xcode adds to every generated Info.plist.
            raw["CFBundleIdentifier"] = .string("$(PRODUCT_BUNDLE_IDENTIFIER)")
            raw["CFBundleShortVersionString"] = .string("$(MARKETING_VERSION)")
            raw["CFBundleVersion"] = .string("$(CURRENT_PROJECT_VERSION)")
            raw["CFBundleExecutable"] = .string("$(EXECUTABLE_NAME)")
            raw["CFBundleName"] = .string("$(PRODUCT_NAME)")
            for (key, value) in settings.values where key.hasPrefix("INFOPLIST_KEY_") {
                raw[String(key.dropFirst("INFOPLIST_KEY_".count))] = .string(value)
            }
        }

        var fileURL: URL?
        var keysFromFile = Set<String>()
        var unreadable = false
        if let path = settings.value("INFOPLIST_FILE"), !path.isEmpty {
            let url = PathUtilities.resolve(path, relativeTo: project.sourceRoot)
            fileURL = url
            let relative = PathUtilities.relativePath(of: url, to: root)
            if let data = FileManager.default.contents(atPath: url.path) {
                if
                    let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
                    let dictionary = PlistValue(foundation: object)?.dictionaryValue {
                    // Values in the file take precedence over generated keys.
                    raw.merge(dictionary) { _, file in file }
                    keysFromFile = Set(dictionary.keys)
                } else {
                    unreadable = true
                    appendOnce(ParseIssue(kind: .malformed, relativePath: relative, message: "Info.plist is not a valid property list."), to: &issues)
                }
            } else {
                unreadable = true
                appendOnce(ParseIssue(kind: .missingReference, relativePath: relative, message: "Info.plist referenced by INFOPLIST_FILE was not found."), to: &issues)
            }
        }

        guard generated || fileURL != nil else { return nil }
        return InfoPlist(
            url: fileURL,
            isGenerated: generated,
            raw: raw,
            resolved: raw.mapValues { substitute($0, settings: settings) },
            keysFromFile: keysFromFile,
            isUnreadable: unreadable
        )
    }

    private func entitlements(settings: BuildSettings, project: XcodeProject, issues: inout [ParseIssue]) -> EntitlementsFile? {
        guard let path = settings.value("CODE_SIGN_ENTITLEMENTS"), !path.isEmpty else { return nil }
        let url = PathUtilities.resolve(path, relativeTo: project.sourceRoot)
        let relative = PathUtilities.relativePath(of: url, to: root)
        guard let data = FileManager.default.contents(atPath: url.path) else {
            appendOnce(ParseIssue(kind: .missingReference, relativePath: relative, message: "Entitlements file referenced by CODE_SIGN_ENTITLEMENTS was not found."), to: &issues)
            return EntitlementsFile(url: url, contents: nil)
        }
        guard
            let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dictionary = PlistValue(foundation: object)?.dictionaryValue
        else {
            appendOnce(ParseIssue(kind: .malformed, relativePath: relative, message: "Entitlements file is not a valid property list."), to: &issues)
            return EntitlementsFile(url: url, contents: nil)
        }
        return EntitlementsFile(url: url, contents: dictionary)
    }

    private func appendOnce(_ issue: ParseIssue, to issues: inout [ParseIssue]) {
        if !issues.contains(issue) { issues.append(issue) }
    }

    private func substitute(_ value: PlistValue, settings: BuildSettings) -> PlistValue {
        switch value {
        case .string(let string): return .string(settings.expand(string))
        case .array(let array): return .array(array.map { substitute($0, settings: settings) })
        case .dictionary(let dictionary): return .dictionary(dictionary.mapValues { substitute($0, settings: settings) })
        default: return value
        }
    }
}
