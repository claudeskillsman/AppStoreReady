import Foundation

/// ASR008: credentials compiled into an app can be extracted from the binary.
///
/// Findings never include the secret itself, only the kind of credential,
/// its location, and its length.
public struct HardcodedSecretRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR008",
        title: "Hardcoded secrets",
        description: "Searches source, property list, configuration, and scheme files for values that look like credentials: cloud provider keys, API tokens, private keys, and high-entropy values assigned to names such as apiKey or secret. Detected values are never printed.",
        rationale: "Anything compiled into an app or bundled as a resource can be extracted by anyone who downloads it, so embedded credentials should be treated as public.",
        category: .security,
        references: [
            Reference("Storing keys in the keychain", "https://developer.apple.com/documentation/security/storing-keys-in-the-keychain"),
        ]
    )

    /// Lines containing this marker are skipped.
    public static let suppressionMarker = "appstoreready:ignore"

    struct Detector {
        let kind: String
        let pattern: TextPattern
        /// Index of the capture group holding the secret value.
        let group: Int
        let severity: Severity
        let confidence: Confidence
        let isGeneric: Bool
        let skipFiles: Set<String>
    }

    static let detectors: [Detector] = [
        Detector(kind: "AWS access key ID", pattern: TextPattern(#"\b((?:AKIA|ASIA)[0-9A-Z]{16})\b"#), group: 1, severity: .error, confidence: .high, isGeneric: false, skipFiles: []),
        Detector(kind: "AWS secret access key", pattern: TextPattern(#"aws_?secret_?access_?key["']?\s*[:=]\s*["']?([A-Za-z0-9/+=]{40})"#, caseInsensitive: true), group: 1, severity: .error, confidence: .high, isGeneric: false, skipFiles: []),
        Detector(kind: "GitHub token", pattern: TextPattern(#"\b(gh[pousr]_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{22,255})\b"#), group: 1, severity: .error, confidence: .high, isGeneric: false, skipFiles: []),
        Detector(kind: "Stripe live secret key", pattern: TextPattern(#"\b((?:sk|rk)_live_[0-9A-Za-z]{20,})\b"#), group: 1, severity: .error, confidence: .high, isGeneric: false, skipFiles: []),
        Detector(kind: "Slack token", pattern: TextPattern(#"\b(xox[abprs]-[0-9A-Za-z-]{10,})\b"#), group: 1, severity: .error, confidence: .high, isGeneric: false, skipFiles: []),
        Detector(kind: "OpenAI or Anthropic API key", pattern: TextPattern(#"\b(sk-(?:proj-|ant-)[A-Za-z0-9_\-]{20,})"#), group: 1, severity: .error, confidence: .high, isGeneric: false, skipFiles: []),
        Detector(kind: "Firebase Cloud Messaging server key", pattern: TextPattern(#"\b(AAAA[A-Za-z0-9_\-]{7}:[A-Za-z0-9_\-]{140})"#), group: 1, severity: .error, confidence: .high, isGeneric: false, skipFiles: []),
        Detector(kind: "Private key", pattern: TextPattern(#"(-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----)"#), group: 1, severity: .error, confidence: .high, isGeneric: false, skipFiles: []),
        // Google API keys for iOS are commonly embedded and restricted by bundle ID;
        // GoogleService-Info.plist is expected to contain one.
        Detector(kind: "Google API key", pattern: TextPattern(#"\b(AIza[0-9A-Za-z_\-]{35})"#), group: 1, severity: .warning, confidence: .medium, isGeneric: false, skipFiles: ["GoogleService-Info.plist"]),
        Detector(
            kind: "Credential-like value",
            pattern: TextPattern(#"\b[A-Za-z0-9_]*(?:api_?key|apikey|secret|access_?token|auth_?token|password|passwd|private_?key)[A-Za-z0-9_]*["']?\s*(?::\s*String\s*)?[:=]\s*@?["']([^"'\s]{12,})["']"#, caseInsensitive: true),
            group: 1, severity: .warning, confidence: .medium, isGeneric: true, skipFiles: []
        ),
        Detector(
            kind: "Credential-like build setting",
            pattern: TextPattern(#"^\s*[A-Za-z0-9_]*(?:API_?KEY|SECRET|ACCESS_?TOKEN|AUTH_?TOKEN|PASSWORD)[A-Za-z0-9_]*\s*=\s*"?([^"\s;$]{12,})"?\s*;?\s*$"#, caseInsensitive: true),
            group: 1, severity: .warning, confidence: .medium, isGeneric: true, skipFiles: []
        ),
    ]

    /// `<key>apiKey</key><string>value</string>` in XML property lists.
    static let plistPair = TextPattern(#"<key>\s*([^<]*(?:api_?key|apikey|secret|access_?token|auth_?token|password)[^<]*)</key>\s*<string>\s*([^<\s]{12,})\s*</string>"#, caseInsensitive: true)

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        var findings: [Finding] = []
        for file in context.files {
            findings += scan(file)
        }
        if findings.isEmpty {
            return [finding(
                "No hardcoded secrets detected",
                message: "No credential patterns were found in \(context.files.count) scanned text file(s). Pattern matching cannot find every secret.",
                severity: .pass,
                confidence: .medium
            )]
        }
        return findings
    }

    func scan(_ file: SourceFile) -> [Finding] {
        let fileName = (file.relativePath as NSString).lastPathComponent
        let inTests = isTestPath(file.relativePath)
        var findings: [Finding] = []
        var reportedLines = Set<Int>()

        let lines = file.lines
        for (index, lineSubstring) in lines.enumerated() {
            let line = String(lineSubstring)
            if line.contains(Self.suppressionMarker) { continue }
            var matchedSpecific = false
            for detector in Self.detectors where !detector.skipFiles.contains(fileName) {
                if detector.isGeneric && matchedSpecific { continue }
                if detector.kind == "Credential-like build setting" && !(file.kind == .xcconfig || file.kind == .environment || file.relativePath.hasSuffix(".pbxproj")) {
                    continue
                }
                guard let match = detector.pattern.firstMatch(in: line), let value = match[detector.group] else { continue }
                if detector.isGeneric && !looksLikeSecret(value) { continue }
                if !detector.isGeneric { matchedSpecific = true }
                guard reportedLines.insert(index + 1).inserted else { continue }
                findings.append(makeFinding(kind: detector.kind, value: value, severity: detector.severity, confidence: detector.confidence, file: file, line: index + 1, inTests: inTests))
            }
        }

        if file.kind == .plist {
            let text = file.contents
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for result in Self.plistPair.expression.matches(in: text, options: [], range: range) {
                guard let valueRange = Range(result.range(at: 2), in: text) else { continue }
                let value = String(text[valueRange])
                guard looksLikeSecret(value) else { continue }
                let lineNumber = text[..<valueRange.lowerBound].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
                if lines.indices.contains(lineNumber - 1), lines[lineNumber - 1].contains(Self.suppressionMarker) { continue }
                guard reportedLines.insert(lineNumber).inserted else { continue }
                findings.append(makeFinding(kind: "Credential-like value", value: value, severity: .warning, confidence: .medium, file: file, line: lineNumber, inTests: inTests))
            }
        }
        return findings
    }

    private func makeFinding(kind: String, value: String, severity: Severity, confidence: Confidence, file: SourceFile, line: Int, inTests: Bool) -> Finding {
        let effectiveSeverity: Severity = inTests && severity == .error ? .warning : severity
        var evidence = ["\(kind), value \(Redactor.describe(value))"]
        if inTests {
            evidence.append("File is in a test or fixture directory and is probably not shipped in the app.")
        }
        return finding(
            "Potential hardcoded secret detected",
            message: "\(file.relativePath):\(line) contains a value matching the pattern for: \(kind). Anything compiled into an app or bundled as a resource can be extracted by anyone who downloads it.",
            severity: effectiveSeverity,
            confidence: inTests ? .low : confidence,
            file: file.relativePath,
            line: line,
            evidence: evidence,
            fix: "Remove the value from the project, rotate the credential, and fetch it at runtime from your server or store it in the Keychain. If this is intentional, add '\(Self.suppressionMarker)' to the line."
        )
    }

    /// Filters out placeholders and low-entropy values for generic detectors.
    func looksLikeSecret(_ value: String) -> Bool {
        let lowered = value.lowercased()
        let placeholders = ["your", "xxxx", "example", "placeholder", "changeme", "dummy", "sample", "redacted", "<", "$(", "${", "insert", "replace", "todo", "fake", "test", "1234"]
        if placeholders.contains(where: { lowered.contains($0) }) { return false }
        if value.hasPrefix("NS") && value.hasSuffix("Description") { return false }
        // Identifiers and key paths are not secrets.
        if value.allSatisfy({ $0.isLetter || $0 == "_" || $0 == "." }) { return false }
        return Redactor.entropy(value) >= 3.0
    }
}
