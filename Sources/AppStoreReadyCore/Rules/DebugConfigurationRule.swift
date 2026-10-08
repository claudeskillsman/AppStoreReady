import Foundation

/// ASR009: archives should not be built with debug settings.
public struct DebugConfigurationRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR009",
        title: "Debug configuration",
        description: "Checks the configuration used to archive each target: flags schemes whose Archive action uses a Debug configuration, and archive configurations with unoptimized code or DEBUG compilation conditions.",
        category: .buildSettings,
        documentationURL: URL(string: "https://developer.apple.com/documentation/xcode/customizing-the-build-schemes-for-a-project")
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.flatMap { evaluate($0, context: context) }
    }

    private func evaluate(_ target: ResolvedTarget, context: ScanContext) -> [Finding] {
        let settings = target.buildSettings
        let configuration = target.configurationName
        var problems: [String] = []

        if case .schemeArchive(let scheme) = target.configurationSource, configuration.lowercased().contains("debug") {
            problems.append("Scheme '\(scheme)' archives with the '\(configuration)' configuration")
        }
        if settings.value("SWIFT_OPTIMIZATION_LEVEL") == "-Onone" {
            problems.append("SWIFT_OPTIMIZATION_LEVEL = -Onone (no optimization)")
        }
        if settings.value("GCC_OPTIMIZATION_LEVEL") == "0" {
            problems.append("GCC_OPTIMIZATION_LEVEL = 0 (no optimization)")
        }
        let conditions = (settings.value("SWIFT_ACTIVE_COMPILATION_CONDITIONS") ?? "").split(separator: " ")
        if conditions.contains("DEBUG") {
            problems.append("SWIFT_ACTIVE_COMPILATION_CONDITIONS includes DEBUG")
        }
        let definitions = (settings.value("GCC_PREPROCESSOR_DEFINITIONS") ?? "").split(separator: " ")
        if definitions.contains(where: { $0 == "DEBUG" || $0 == "DEBUG=1" }) {
            problems.append("GCC_PREPROCESSOR_DEFINITIONS defines DEBUG")
        }

        let source = "Configuration inspected: \(configuration) (\(target.configurationSource.description))"
        var findings: [Finding] = []
        if !problems.isEmpty {
            findings.append(finding(
                "Debug configuration selected for archiving",
                message: "The configuration used to archive '\(target.name)' has debug settings. Debug builds are slower, may include test-only code paths, and are not what you tested as a release.",
                severity: .warning,
                confidence: .high,
                file: archiveFile(for: target, context: context),
                target: target,
                evidence: problems + [source],
                fix: "In Product › Scheme › Edit Scheme › Archive, choose the Release configuration, and keep -Onone and DEBUG out of the configuration you ship."
            ))
        } else {
            findings.append(finding(
                "Archive configuration uses release settings",
                message: "'\(target.name)' archives with '\(configuration)', which has optimization enabled and no DEBUG condition.",
                severity: .pass,
                confidence: .high,
                file: archiveFile(for: target, context: context),
                target: target,
                evidence: [source]
            ))
        }

        switch target.configurationSource {
        case .releaseByName, .projectDefault:
            findings.append(finding(
                "No shared scheme found",
                message: "No scheme with an Archive action builds '\(target.name)', so AppStoreReady assumed '\(configuration)'. Shared schemes make archive settings visible to other developers and CI.",
                severity: .info,
                confidence: .high,
                file: context.projectFile(for: target),
                target: target,
                fix: "Mark the app's scheme as Shared (Product › Scheme › Manage Schemes) and commit it."
            ))
        default:
            break
        }
        return findings
    }

    private func archiveFile(for target: ResolvedTarget, context: ScanContext) -> String {
        if case .schemeArchive(let name) = target.configurationSource,
           let scheme = target.project.schemes.first(where: { $0.name == name }) {
            return context.relativePath(scheme.url)
        }
        return context.projectFile(for: target)
    }
}
