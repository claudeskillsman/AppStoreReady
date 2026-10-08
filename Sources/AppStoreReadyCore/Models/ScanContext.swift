import Foundation

/// Why a particular build configuration was chosen for a target.
public enum ConfigurationSource: Equatable, Sendable {
    /// Passed explicitly with `--configuration`.
    case userSpecified
    /// The Archive action of a scheme.
    case schemeArchive(scheme: String)
    /// No scheme was found; a configuration named "Release" exists.
    case releaseByName
    /// Fallback: the project's default configuration.
    case projectDefault

    public var description: String {
        switch self {
        case .userSpecified: return "selected with --configuration"
        case .schemeArchive(let scheme): return "Archive action of scheme '\(scheme)'"
        case .releaseByName: return "configuration named Release (no scheme found)"
        case .projectDefault: return "project default configuration (no scheme found)"
        }
    }
}

/// The effective Info.plist of a target for one configuration.
public struct InfoPlist: Sendable {
    /// The Info.plist file on disk, if the target uses one.
    public let url: URL?
    /// Whether Xcode generates (part of) the Info.plist from build settings.
    public let isGenerated: Bool
    /// Values before build setting substitution.
    public let raw: [String: PlistValue]
    /// Values after `$(VARIABLE)` substitution.
    public let resolved: [String: PlistValue]
    /// Keys whose value comes from the Info.plist file rather than build settings.
    public let keysFromFile: Set<String>
    /// True when the Info.plist file exists but could not be parsed. Rules
    /// skip such targets; the parse failure is reported by ASR001.
    public let isUnreadable: Bool

    public func string(_ key: String) -> String? {
        resolved[key]?.stringValue
    }

    public func rawString(_ key: String) -> String? {
        raw[key]?.stringValue
    }
}

/// A target with build settings resolved for the configuration that will be archived.
public struct ResolvedTarget: Sendable {
    public let target: ProjectTarget
    public let project: XcodeProject
    public let configurationName: String
    public let configurationSource: ConfigurationSource
    public let buildSettings: BuildSettings
    /// Build settings for every configuration of the target, keyed by name.
    public let allConfigurations: [String: BuildSettings]
    public let infoPlist: InfoPlist?

    public var name: String { target.name }
    public var productType: ProductType { target.productType }
}

/// A text file found under the scan root.
public struct SourceFile: Sendable {
    public enum Kind: String, Sendable {
        case swift, objectiveC, header, plist, json, xcconfig, strings, script, environment, other
    }

    public let url: URL
    /// Standardized absolute path.
    public let path: String
    public let relativePath: String
    public let kind: Kind
    public let contents: String

    public var isCode: Bool {
        kind == .swift || kind == .objectiveC || kind == .header
    }

    public var lines: [Substring] {
        contents.split(separator: "\n", omittingEmptySubsequences: false)
    }
}

/// A `PrivacyInfo.xcprivacy` file.
public struct PrivacyManifest: Sendable {
    public let url: URL
    public let path: String
    public let relativePath: String
    /// Nil when the file could not be parsed.
    public let contents: [String: PlistValue]?

    /// API categories declared under `NSPrivacyAccessedAPITypes`, with their reasons.
    public var declaredAPICategories: [String: [String]] {
        var result: [String: [String]] = [:]
        for entry in contents?["NSPrivacyAccessedAPITypes"]?.arrayValue ?? [] {
            guard let category = entry["NSPrivacyAccessedAPIType"]?.stringValue else { continue }
            let reasons = entry["NSPrivacyAccessedAPITypeReasons"]?.arrayValue?.compactMap(\.stringValue) ?? []
            result[category, default: []].append(contentsOf: reasons)
        }
        return result
    }
}

/// An `.appiconset` inside an asset catalog.
public struct AppIconSet: Sendable {
    public let name: String
    public let url: URL
    public let path: String
    public let relativePath: String
    /// Nil when `Contents.json` is missing or unreadable.
    public let images: [Image]?

    public struct Image: Sendable {
        public let filename: String?
        public let size: String?
        public let idiom: String?
        public let fileExists: Bool
    }
}

/// A problem reading a project file.
public struct ParseIssue: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case unreadable, malformed, missingReference
    }

    public let kind: Kind
    public let relativePath: String
    public let message: String
}

/// Everything the rules can look at. Built once by `ProjectScanner`.
public struct ScanContext: Sendable {
    public let inputURL: URL
    public let rootURL: URL
    public let projects: [XcodeProject]
    /// Distributable targets (apps and extensions), resolved.
    public let targets: [ResolvedTarget]
    public let files: [SourceFile]
    public let privacyManifests: [PrivacyManifest]
    public let appIconSets: [AppIconSet]
    public let parseIssues: [ParseIssue]

    public init(
        inputURL: URL,
        rootURL: URL,
        projects: [XcodeProject],
        targets: [ResolvedTarget],
        files: [SourceFile],
        privacyManifests: [PrivacyManifest],
        appIconSets: [AppIconSet],
        parseIssues: [ParseIssue]
    ) {
        self.inputURL = inputURL
        self.rootURL = rootURL
        self.projects = projects
        self.targets = targets
        self.files = files
        self.privacyManifests = privacyManifests
        self.appIconSets = appIconSets
        self.parseIssues = parseIssues
    }

    public func relativePath(_ url: URL) -> String {
        PathUtilities.relativePath(of: url, to: rootURL)
    }

    /// Code files that belong to `target`. When target membership is unknown
    /// all code files under the root are returned and `exact` is false.
    public func codeFiles(for target: ResolvedTarget) -> (files: [SourceFile], exact: Bool) {
        let code = files.filter(\.isCode)
        guard target.target.hasKnownMembership else { return (code, false) }
        return (code.filter { target.target.contains(path: $0.path) }, true)
    }
}
