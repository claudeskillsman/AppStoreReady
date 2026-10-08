import Foundation

/// A developer's decision to hide a finding, read from `.appstoreready.yml`.
public struct Suppression: Codable, Equatable, Sendable {
    /// Rule identifier, for example `ASR008`.
    public let rule: String
    /// Why the finding is acceptable. Required.
    public let reason: String
    /// Last day (inclusive, `YYYY-MM-DD`) on which the suppression applies.
    public let expires: String?
    /// Optional file path or glob (`*`, `**`) the finding's file must match.
    public let path: String?
    /// Optional target name the finding must belong to.
    public let target: String?
    /// Line of the entry in the configuration file.
    public let line: Int

    public init(rule: String, reason: String, expires: String? = nil, path: String? = nil, target: String? = nil, line: Int = 0) {
        self.rule = rule
        self.reason = reason
        self.expires = expires
        self.path = path
        self.target = target
        self.line = line
    }

    /// Whether the suppression has expired on `today` (`YYYY-MM-DD`).
    public func isExpired(today: String) -> Bool {
        guard let expires else { return false }
        return today > expires
    }

    public func matches(_ finding: Finding) -> Bool {
        guard finding.ruleID.caseInsensitiveCompare(rule) == .orderedSame else { return false }
        if let target, finding.target != target { return false }
        if let path {
            guard let file = finding.file, Suppression.glob(path, matches: file) else { return false }
        }
        return true
    }

    static func glob(_ pattern: String, matches path: String) -> Bool {
        if pattern.hasSuffix("/") { return path.hasPrefix(pattern) }
        guard pattern.contains("*") || pattern.contains("?") else { return path == pattern }
        let characters = Array(pattern)
        var regex = "^"
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "*", index + 1 < characters.count, characters[index + 1] == "*" {
                if index + 2 < characters.count, characters[index + 2] == "/" {
                    regex += "(?:.*/)?"
                    index += 3
                } else {
                    regex += ".*"
                    index += 2
                }
                continue
            }
            switch character {
            case "*": regex += "[^/]*"
            case "?": regex += "[^/]"
            default: regex += NSRegularExpression.escapedPattern(for: String(character))
            }
            index += 1
        }
        regex += "$"
        return path.range(of: regex, options: .regularExpression) != nil
    }
}

/// Errors in `.appstoreready.yml`. These stop the scan (exit code 2) so a
/// typo can never silently disable a suppression or hide a finding.
public struct ConfigurationError: Error, Equatable, CustomStringConvertible {
    public let file: String
    public let line: Int
    public let message: String

    public init(file: String, line: Int, message: String) {
        self.file = file
        self.line = line
        self.message = message
    }

    public var description: String {
        line > 0 ? "\(file):\(line): \(message)" : "\(file): \(message)"
    }
}

/// Contents of `.appstoreready.yml`.
///
/// The file format is a small, strict subset of YAML:
///
/// ```yaml
/// suppressions:
///   - rule: ASR008
///     reason: "Public demo key, restricted to the demo bundle ID"
///     expires: 2027-01-31        # optional
///     path: App/DemoKeys.swift   # optional, supports * and **
///     target: App                # optional
/// ```
public struct AppStoreReadyConfiguration: Equatable, Sendable {
    public static let fileName = ".appstoreready.yml"

    public var suppressions: [Suppression]

    public init(suppressions: [Suppression] = []) {
        self.suppressions = suppressions
    }

    /// Loads the configuration file, or returns nil when it does not exist.
    public static func load(from url: URL, knownRuleIDs: Set<String>) throws -> AppStoreReadyConfiguration? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw ConfigurationError(file: url.lastPathComponent, line: 0, message: "The file could not be read.")
        }
        return try parse(String(decoding: data, as: UTF8.self), fileName: url.lastPathComponent, knownRuleIDs: knownRuleIDs)
    }

    private static let itemKeys: Set<String> = ["rule", "reason", "expires", "path", "target"]
    private static let datePattern = TextPattern(#"^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$"#)

    public static func parse(_ text: String, fileName: String = fileName, knownRuleIDs: Set<String>) throws -> AppStoreReadyConfiguration {
        func fail(_ line: Int, _ message: String) -> ConfigurationError {
            ConfigurationError(file: fileName, line: line, message: message)
        }

        var items: [(line: Int, values: [String: String])] = []
        var section: String?
        var itemIndent: Int?

        for (offset, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = offset + 1
            let line = stripComment(rawLine)
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if line.contains("\t") { throw fail(lineNumber, "Use spaces, not tabs, for indentation.") }
            let indent = line.prefix { $0 == " " }.count
            let content = String(line.dropFirst(indent))

            if indent == 0 {
                guard let (key, value) = keyValue(content) else { throw fail(lineNumber, "Expected 'key: value'.") }
                switch key {
                case "version":
                    guard value == "1" else { throw fail(lineNumber, "Unsupported version '\(value)'; only version 1 exists.") }
                    section = nil
                case "suppressions":
                    guard value.isEmpty || value == "[]" else { throw fail(lineNumber, "'suppressions' must be a list of entries.") }
                    section = "suppressions"
                default:
                    throw fail(lineNumber, "Unknown setting '\(key)'. Supported settings: version, suppressions.")
                }
                continue
            }

            guard section == "suppressions" else { throw fail(lineNumber, "Unexpected indentation.") }
            var body = content
            if content.hasPrefix("- ") || content == "-" {
                itemIndent = indent + 2
                items.append((lineNumber, [:]))
                body = String(content.dropFirst(min(2, content.count)))
                if body.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            } else {
                guard let expected = itemIndent, indent == expected, !items.isEmpty else {
                    throw fail(lineNumber, "Each suppression must start with '- ' and its keys must be aligned.")
                }
            }
            guard let (key, value) = keyValue(body) else { throw fail(lineNumber, "Expected 'key: value'.") }
            guard itemKeys.contains(key) else {
                throw fail(lineNumber, "Unknown suppression key '\(key)'. Supported keys: rule, reason, expires, path, target.")
            }
            guard items[items.count - 1].values[key] == nil else { throw fail(lineNumber, "Duplicate key '\(key)'.") }
            items[items.count - 1].values[key] = value
        }

        let suppressions = try items.map { item -> Suppression in
            let values = item.values
            guard let rule = values["rule"], !rule.isEmpty else { throw fail(item.line, "Suppression is missing 'rule'.") }
            guard knownRuleIDs.contains(rule.uppercased()) else { throw fail(item.line, "Unknown rule '\(rule)'.") }
            guard let reason = values["reason"], !reason.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw fail(item.line, "Suppression of \(rule) needs a 'reason' explaining why the finding is acceptable.")
            }
            if let expires = values["expires"], !datePattern.matches(expires) {
                throw fail(item.line, "'expires' must be a date in the form YYYY-MM-DD.")
            }
            return Suppression(
                rule: rule.uppercased(),
                reason: reason,
                expires: values["expires"],
                path: values["path"].flatMap { $0.isEmpty ? nil : $0 },
                target: values["target"].flatMap { $0.isEmpty ? nil : $0 },
                line: item.line
            )
        }
        return AppStoreReadyConfiguration(suppressions: suppressions)
    }

    /// Removes a `#` comment that is not inside quotes.
    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        var previous: Character = " "
        for (index, character) in zip(line.indices, line) {
            if let open = quote {
                if character == open { quote = nil }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character == "#" && (previous == " " || index == line.startIndex) {
                return String(line[..<index])
            }
            previous = character
        }
        return line
    }

    private static func keyValue(_ text: String) -> (String, String)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let key = text[..<colon].trimmingCharacters(in: .whitespaces)
        var value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.contains(" ") else { return nil }
        if value.count >= 2, let first = value.first, first == "\"" || first == "'", value.last == first {
            value = String(value.dropFirst().dropLast())
            if first == "\"" { value = value.replacingOccurrences(of: "\\\"", with: "\"") }
        }
        return (key, value)
    }
}
