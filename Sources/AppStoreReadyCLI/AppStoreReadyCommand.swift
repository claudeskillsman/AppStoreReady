import AppStoreReadyCore
import ArgumentParser
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct AppStoreReadyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "appstoreready",
        abstract: "Audit an Xcode project for likely App Store submission problems.",
        discussion: """
        AppStoreReady reads project files only. It never runs build scripts or \
        project code, never uploads anything, and never prints detected secrets.

        Exit codes: 0 = no findings at or above --fail-on, 1 = findings at or \
        above --fail-on, 2 = the scan could not run, 64 = invalid arguments.
        """,
        version: AppStoreReadyVersion.current,
        subcommands: [Scan.self, Rules.self],
        defaultSubcommand: Scan.self
    )
}

extension ReportFormat: ExpressibleByArgument {}
extension FailureThreshold: ExpressibleByArgument {}

struct Scan: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Scan an .xcodeproj, .xcworkspace, or a directory containing one."
    )

    @Argument(help: "Path to an .xcodeproj, .xcworkspace, or directory.", completion: .file())
    var path: String = "."

    @Option(name: .shortAndLong, help: "Output format: text or json.")
    var format: ReportFormat = .text

    @Option(name: .shortAndLong, help: "Write the report to a file instead of standard output.")
    var output: String?

    @Option(name: .shortAndLong, help: "Build configuration to inspect. Defaults to each scheme's Archive configuration, then Release.")
    var configuration: String?

    @Option(name: .customLong("fail-on"), help: "Lowest severity that causes exit code 1: error, warning, or never.")
    var failOn: FailureThreshold = .error

    @Option(name: .customLong("disable"), parsing: .upToNextOption, help: "Rule identifiers to skip, for example ASR008.")
    var disabledRules: [String] = []

    @Flag(name: .customLong("no-color"), help: "Disable colored output.")
    var noColor = false

    @Flag(name: .shortAndLong, help: "Show details for passing checks.")
    var verbose = false

    func validate() throws {
        let known = Set(RuleRegistry.builtIn.map { $0.metadata.id.uppercased() })
        for id in disabledRules where !known.contains(id.uppercased()) {
            throw ValidationError("Unknown rule '\(id)'. Run 'appstoreready rules' to list rule identifiers.")
        }
    }

    func run() throws {
        let report: ScanReport
        do {
            report = try AuditEngine.audit(
                path: path,
                options: ScanOptions(configuration: configuration),
                disabledRuleIDs: Set(disabledRules)
            )
        } catch let error as ScanError {
            FileHandle.standardError.write(Data("error: \(error.description)\n".utf8))
            throw ExitCode(ExitStatus.scanFailed.rawValue)
        }

        let rendered: String
        switch format {
        case .json:
            rendered = try JSONReporter().render(report)
        case .text:
            let colorAllowed = !noColor && output == nil && ProcessInfo.processInfo.environment["NO_COLOR"] == nil
            rendered = TextReporter(useColor: colorAllowed && isatty(STDOUT_FILENO) != 0, verbose: verbose).render(report)
        }

        if let output {
            try (rendered + "\n").write(toFile: output, atomically: true, encoding: .utf8)
        } else {
            print(rendered)
        }

        let status = ExitStatus.forReport(report, threshold: failOn)
        if status != .success {
            throw ExitCode(status.rawValue)
        }
    }
}

struct Rules: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List the checks AppStoreReady runs.")

    @Option(name: .shortAndLong, help: "Output format: text or json.")
    var format: ReportFormat = .text

    func run() throws {
        let rules = RuleRegistry.builtIn.map(\.metadata)
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            print(String(decoding: try encoder.encode(rules), as: UTF8.self))
        case .text:
            for rule in rules {
                print("\(rule.id)  \(rule.title)  [\(rule.category.rawValue)]")
                print("        \(rule.description)")
                if let url = rule.documentationURL {
                    print("        \(url.absoluteString)")
                }
            }
        }
    }
}
