import Foundation

/// ASR017: code signing settings of the archive configuration.
public struct SigningConfigurationRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR017",
        title: "Signing configuration",
        description: "Checks the archive configuration's signing settings: a development team for automatic signing, a provisioning profile for manual signing, signing not disabled, and the same team for an app and its extensions.",
        rationale: "Builds uploaded to App Store Connect must be signed for distribution. Missing teams or profiles make archiving or exporting fail, and an app and its extensions are expected to be signed by the same team.",
        category: .signing,
        references: [
            Reference("Code signing build settings", "https://developer.apple.com/documentation/xcode/build-settings-reference#Signing"),
            Reference("Distributing your app for beta testing and releases", "https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases"),
        ]
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.map { evaluate($0, context: context) }
    }

    private func evaluate(_ target: ResolvedTarget, context: ScanContext) -> Finding {
        let settings = target.buildSettings
        let file = context.projectFile(for: target)
        let team = settings.value("DEVELOPMENT_TEAM")?.trimmingCharacters(in: .whitespaces) ?? ""
        let style = settings.value("CODE_SIGN_STYLE") ?? "Automatic"
        let configuration = target.configurationName

        if settings.value("CODE_SIGNING_ALLOWED")?.uppercased() == "NO" || settings.value("CODE_SIGNING_REQUIRED")?.uppercased() == "NO" {
            return finding(
                "Code signing is disabled",
                message: "Code signing is turned off for '\(target.name)' in \(configuration). App Store builds must be signed.",
                severity: .error,
                confidence: .high,
                classification: .verifiedIssue,
                file: file,
                target: target,
                evidence: ["CODE_SIGNING_ALLOWED = \(settings.value("CODE_SIGNING_ALLOWED") ?? "YES")", "CODE_SIGNING_REQUIRED = \(settings.value("CODE_SIGNING_REQUIRED") ?? "YES")"],
                fix: "Remove CODE_SIGNING_ALLOWED = NO / CODE_SIGNING_REQUIRED = NO from the configuration used for archiving."
            )
        }

        if style == "Manual" {
            let profile = settings.value("PROVISIONING_PROFILE_SPECIFIER") ?? settings.value("PROVISIONING_PROFILE") ?? ""
            if profile.isEmpty {
                return finding(
                    "No provisioning profile for manual signing",
                    message: "'\(target.name)' uses manual signing but no provisioning profile is set for \(configuration). The profile may be supplied by your CI or on the command line.",
                    severity: .warning,
                    confidence: .medium,
                    classification: .potentialIssue,
                    file: file,
                    target: target,
                    evidence: ["CODE_SIGN_STYLE = Manual", "PROVISIONING_PROFILE_SPECIFIER is not set"],
                    fix: "Select a distribution provisioning profile in Signing & Capabilities for \(configuration), or switch to automatic signing."
                )
            }
        } else if team.isEmpty {
            return finding(
                "No development team set",
                message: "'\(target.name)' uses automatic signing but DEVELOPMENT_TEAM is empty for \(configuration). Xcode cannot sign the archive without a team, unless your build system passes one in.",
                severity: .warning,
                confidence: .medium,
                classification: .potentialIssue,
                file: file,
                target: target,
                evidence: ["CODE_SIGN_STYLE = \(style)", "DEVELOPMENT_TEAM is not set"],
                fix: "Choose a team in Signing & Capabilities, or set DEVELOPMENT_TEAM in an .xcconfig file."
            )
        }

        if target.productType == .appExtension, let app = containingApp(of: target, context: context) {
            let appTeam = app.buildSettings.value("DEVELOPMENT_TEAM") ?? ""
            if !team.isEmpty, !appTeam.isEmpty, team != appTeam {
                return finding(
                    "Extension signed by a different team",
                    message: "App extension '\(target.name)' uses team \(team) but the app '\(app.name)' uses \(appTeam). An app and the extensions it contains are expected to come from the same team.",
                    severity: .warning,
                    confidence: .medium,
                    classification: .potentialIssue,
                    file: file,
                    target: target,
                    evidence: ["\(app.name): DEVELOPMENT_TEAM = \(appTeam)", "\(target.name): DEVELOPMENT_TEAM = \(team)"],
                    fix: "Use the same DEVELOPMENT_TEAM for every target that ships in the app."
                )
            }
        }

        return finding(
            "Signing configuration present",
            message: "'\(target.name)' has \(style.lowercased()) signing configured for \(configuration).",
            severity: .pass,
            confidence: .medium,
            file: file,
            target: target,
            evidence: team.isEmpty ? ["CODE_SIGN_STYLE = \(style)"] : ["CODE_SIGN_STYLE = \(style)", "DEVELOPMENT_TEAM = \(team)"]
        )
    }
}
