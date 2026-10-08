import Foundation

/// Options that control what the scanner reads.
public struct ScanOptions: Sendable {
    /// Inspect this build configuration instead of the scheme's archive configuration.
    public var configuration: String?
    /// Files larger than this (in bytes) are not read.
    public var maxFileSize: Int
    /// Upper bound on the number of text files read.
    public var maxFileCount: Int

    public init(configuration: String? = nil, maxFileSize: Int = 2_000_000, maxFileCount: Int = 50_000) {
        self.configuration = configuration
        self.maxFileSize = maxFileSize
        self.maxFileCount = maxFileCount
    }
}

/// Reads an Xcode project or workspace from disk and builds a `ScanContext`.
///
/// The scanner only reads files. It never runs build phases, scripts,
/// package plugins, or any other code from the project, and it makes no
/// network requests.
public struct ProjectScanner {
    public let options: ScanOptions

    public init(options: ScanOptions = ScanOptions()) {
        self.options = options
    }

    public func scan(path: String) throws -> ScanContext {
        let inputURL = URL(fileURLWithPath: path).standardizedFileURL
        let discovery = try ProjectDiscovery.discover(inputURL: inputURL)
        let root = discovery.root
        var issues: [ParseIssue] = []

        let projects = discovery.projectURLs.compactMap {
            XcodeProjectLoader.load(projectURL: $0, root: root, issues: &issues)
        }

        if let requested = options.configuration {
            let available = Set(projects.flatMap { $0.targets.flatMap { $0.configurations.map(\.name) } })
            if !projects.isEmpty && !available.contains(requested) {
                throw ScanError.unknownConfiguration(requested, available: available.sorted())
            }
        }

        var workspaceSchemes: [Scheme] = []
        for workspace in discovery.workspaceURLs {
            workspaceSchemes += SchemeParser.schemes(in: workspace, root: root, issues: &issues)
        }

        var resolver = TargetResolver(root: root, requestedConfiguration: options.configuration, workspaceSchemes: workspaceSchemes)
        var targets: [ResolvedTarget] = []
        for project in projects {
            targets += resolver.resolve(project: project, issues: &issues)
        }

        let collected = FileCollector(root: root, maxFileSize: options.maxFileSize, maxFileCount: options.maxFileCount).collect()
        for issue in collected.issues where !issues.contains(issue) {
            issues.append(issue)
        }

        return ScanContext(
            inputURL: inputURL,
            rootURL: root,
            projects: projects,
            targets: targets,
            files: collected.files,
            privacyManifests: collected.privacyManifests,
            appIconSets: collected.appIconSets,
            parseIssues: issues
        )
    }
}
