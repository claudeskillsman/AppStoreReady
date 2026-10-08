import Foundation

/// ASR001: reports project files that could not be read or parsed.
public struct ProjectFilesRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR001",
        title: "Project files are readable",
        description: "Checks that the project file, Info.plist files, privacy manifests, schemes, and asset catalog metadata can be parsed. Malformed files usually break the build, and they prevent the other checks from running.",
        category: .project,
        documentationURL: URL(string: "https://developer.apple.com/documentation/bundleresources/managing-your-app-s-information-property-list")
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        var findings: [Finding] = context.parseIssues.map { issue in
            let isCritical = issue.relativePath.hasSuffix(".pbxproj")
                || issue.relativePath.hasSuffix(".plist")
                || issue.relativePath.hasSuffix(".xcprivacy")
                || issue.kind == .missingReference
            let title: String
            switch issue.kind {
            case .missingReference: title = "Referenced file is missing"
            case .malformed: title = "Malformed project file"
            case .unreadable: title = "Unreadable project file"
            }
            return finding(
                title,
                message: issue.message,
                severity: isCritical ? .error : .warning,
                confidence: .high,
                file: issue.relativePath,
                fix: issue.kind == .missingReference
                    ? "Restore the file or update the build setting that points to it."
                    : "Open the file in Xcode or a property list editor and fix the syntax. Checks that depend on this file were skipped."
            )
        }

        if !context.projects.isEmpty && context.targets.isEmpty {
            findings.append(finding(
                "No app targets found",
                message: "No application or app extension targets were found, so app-specific checks were skipped.",
                severity: .info,
                confidence: .high,
                evidence: context.projects.map { "\(context.relativePath($0.url)): \($0.targets.count) target(s)" }
            ))
        }

        if findings.isEmpty {
            let targetCount = context.targets.count
            findings.append(finding(
                "Project files parsed",
                message: "All project files that were found could be parsed.",
                severity: .pass,
                confidence: .high,
                evidence: ["\(context.projects.count) project(s), \(targetCount) app or extension target(s)"]
            ))
        }
        return findings
    }
}
