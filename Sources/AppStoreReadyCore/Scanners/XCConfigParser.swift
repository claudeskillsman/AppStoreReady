import Foundation

/// Reads `.xcconfig` files, following `#include` directives.
enum XCConfigParser {
    static func parse(url: URL, root: URL, issues: inout [ParseIssue], depth: Int = 0) -> [String: String] {
        guard depth < 8 else { return [:] }
        guard let data = FileManager.default.contents(atPath: url.path) else {
            issues.append(ParseIssue(
                kind: .missingReference,
                relativePath: PathUtilities.relativePath(of: url, to: root),
                message: "Configuration file referenced by the project was not found."
            ))
            return [:]
        }
        let text = String(decoding: data, as: UTF8.self)
        var settings: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            var line = rawLine
            if let comment = line.range(of: "//") {
                line = String(line[..<comment.lowerBound])
            }
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#include") {
                let optional = line.hasPrefix("#include?")
                guard let first = line.firstIndex(of: "\""), let last = line.lastIndex(of: "\""), first < last else { continue }
                let includePath = String(line[line.index(after: first)..<last])
                let includeURL = PathUtilities.resolve(includePath, relativeTo: url.deletingLastPathComponent())
                if optional && !PathUtilities.exists(includeURL) { continue }
                let included = parse(url: includeURL, root: root, issues: &issues, depth: depth + 1)
                settings.merge(included) { _, new in new }
                continue
            }

            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.hasSuffix(";") { value.removeLast() }
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty else { continue }
            settings[key] = value
        }
        return settings
    }
}
