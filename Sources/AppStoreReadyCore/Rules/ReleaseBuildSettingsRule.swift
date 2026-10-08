import Foundation

/// ASR022: recommended settings for the configuration that is archived.
public struct ReleaseBuildSettingsRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR022",
        title: "Release build settings",
        description: "Checks the archive configuration for settings that are usually changed for release builds: dSYM generation (DEBUG_INFORMATION_FORMAT) and testability (ENABLE_TESTABILITY).",
        rationale: "Without dSYM files, crash reports from App Store users cannot be symbolicated. Testability exports internal symbols and disables some optimizations, which is meant for test builds.",
        category: .buildConfiguration,
        references: [
            Reference("Building your app to include debugging information", "https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information"),
            Reference("Build settings reference", "https://developer.apple.com/documentation/xcode/build-settings-reference"),
        ]
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.map { target in
            let settings = target.buildSettings
            var notes: [String] = []
            if let format = settings.value("DEBUG_INFORMATION_FORMAT"), format != "dwarf-with-dsym" {
                notes.append("DEBUG_INFORMATION_FORMAT = \(format) (no dSYM is produced)")
            }
            if settings.bool("ENABLE_TESTABILITY") {
                notes.append("ENABLE_TESTABILITY = YES")
            }
            guard !notes.isEmpty else {
                return finding(
                    "Release build settings follow common practice",
                    message: "'\(target.name)' produces dSYMs and does not enable testability in '\(target.configurationName)'.",
                    severity: .pass,
                    confidence: .high,
                    file: context.projectFile(for: target),
                    target: target
                )
            }
            return finding(
                "Release build settings could be improved",
                message: "The configuration used to archive '\(target.name)' (\(target.configurationName)) has settings that are normally reserved for debug builds.",
                severity: .info,
                confidence: .high,
                classification: .bestPractice,
                file: context.projectFile(for: target),
                target: target,
                evidence: notes,
                fix: "Set DEBUG_INFORMATION_FORMAT to dwarf-with-dsym and ENABLE_TESTABILITY to NO for \(target.configurationName)."
            )
        }
    }
}
