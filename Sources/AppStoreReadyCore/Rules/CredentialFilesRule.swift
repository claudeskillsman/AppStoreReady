import Foundation

/// ASR016: private key and certificate bundle files in the project.
public struct CredentialFilesRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR016",
        title: "Credential files",
        description: "Looks for files that normally hold private keys: PKCS#12 bundles (.p12, .pfx) and Apple auth keys (.p8). Reports an error when such a file is a member of a target and would be copied into the app.",
        rationale: "Files bundled into an app can be extracted by anyone who downloads it. Signing identities and App Store Connect or APNs auth keys must never ship inside an app, and should not be committed to source control.",
        category: .security,
        references: [
            Reference("Storing keys in the keychain", "https://developer.apple.com/documentation/security/storing-keys-in-the-keychain"),
            Reference("Creating API keys for App Store Connect API", "https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api"),
        ]
    )

    static let extensions: [String: String] = [
        "p12": "PKCS#12 certificate bundle",
        "pfx": "PKCS#12 certificate bundle",
        "p8": "private key (.p8, used for App Store Connect API and APNs auth keys)",
    ]

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        var findings: [Finding] = []
        for path in context.allFilePaths {
            let ext = (path as NSString).pathExtension.lowercased()
            guard let kind = Self.extensions[ext] else { continue }
            let absolute = PathUtilities.standardPath(context.rootURL.appendingPathComponent(path))
            let bundledIn = context.targets.filter { $0.target.hasKnownMembership && $0.target.contains(path: absolute) }
            if let target = bundledIn.first {
                findings.append(finding(
                    "Private key file bundled in the app",
                    message: "\(path) is a \(kind) and is a member of '\(target.name)', so it is copied into the app bundle.",
                    severity: .error,
                    confidence: .high,
                    classification: .verifiedIssue,
                    file: path,
                    target: target,
                    evidence: ["Target membership: \(bundledIn.map(\.name).joined(separator: ", "))"],
                    fix: "Remove the file from the target, revoke and rotate the key, and keep it out of the repository."
                ))
            } else {
                let inTests = isTestPath(path)
                findings.append(finding(
                    "Private key file in the project folder",
                    message: "\(path) looks like a \(kind). It is not part of any app target, but it is in the project folder and may be committed to source control.",
                    severity: inTests ? .info : .warning,
                    confidence: inTests ? .low : .medium,
                    classification: inTests ? .bestPractice : .potentialIssue,
                    file: path,
                    fix: "Move the file out of the repository (for example into the CI secret store), and rotate the key if it was ever committed."
                ))
            }
        }
        if findings.isEmpty {
            findings.append(finding(
                "No credential files found",
                message: "No .p12, .pfx, or .p8 files were found under the scan root.",
                severity: .pass,
                confidence: .high
            ))
        }
        return findings
    }
}
