import Foundation

/// A small wrapper around `NSRegularExpression` (available on macOS and Linux).
struct TextPattern: @unchecked Sendable {
    let expression: NSRegularExpression

    init(_ pattern: String, caseInsensitive: Bool = false) {
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        // Patterns are compile-time constants; a failure is a programming error.
        // swiftlint:disable:next force_try
        expression = try! NSRegularExpression(pattern: pattern, options: options)
    }

    func matches(_ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.firstMatch(in: text, options: [], range: range) != nil
    }

    /// All matches, each as the full match plus capture groups (nil when a group did not participate).
    func allMatches(in text: String) -> [[String?]] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return expression.matches(in: text, options: [], range: range).map { result in
            (0..<result.numberOfRanges).map { index in
                let nsRange = result.range(at: index)
                guard nsRange.location != NSNotFound, let range = Range(nsRange, in: text) else { return nil }
                return String(text[range])
            }
        }
    }

    func firstMatch(in text: String) -> [String?]? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let result = expression.firstMatch(in: text, options: [], range: range) else { return nil }
        return (0..<result.numberOfRanges).map { index in
            let nsRange = result.range(at: index)
            guard nsRange.location != NSNotFound, let range = Range(nsRange, in: text) else { return nil }
            return String(text[range])
        }
    }
}

enum SourceText {
    /// Returns true for lines that are entirely a comment, so API names
    /// mentioned in documentation do not count as usage.
    static func isCommentLine(_ line: Substring) -> Bool {
        let trimmed = line.drop { $0 == " " || $0 == "\t" }
        return trimmed.hasPrefix("//") || trimmed.hasPrefix("*") || trimmed.hasPrefix("/*")
    }
}
