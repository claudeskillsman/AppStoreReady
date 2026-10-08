import Foundation

/// Layered, resolvable Xcode build settings for one target and configuration.
public struct BuildSettings: Sendable {
    /// Values after layering and `$(inherited)` resolution, before variable expansion.
    public let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }

    /// Layers settings the way Xcode does: later layers override earlier ones,
    /// and `$(inherited)` refers to the value from the layers below.
    public init(layers: [[String: String]]) {
        var result: [String: String] = [:]
        for layer in layers {
            for (key, value) in BuildSettings.unconditional(layer) {
                let inherited = result[key] ?? ""
                var newValue = value
                var didInherit = false
                for token in ["$(inherited)", "${inherited}", "$(INHERITED)"] where newValue.contains(token) {
                    newValue = newValue.replacingOccurrences(of: token, with: inherited)
                    didInherit = true
                }
                if didInherit {
                    newValue = newValue
                        .split(separator: " ", omittingEmptySubsequences: true)
                        .joined(separator: " ")
                }
                result[key] = newValue
            }
        }
        self.values = result
    }

    /// Drops conditional keys such as `OTHER_LDFLAGS[sdk=iphoneos*]`,
    /// unless no unconditional value exists for that setting.
    private static func unconditional(_ layer: [String: String]) -> [String: String] {
        var plain: [String: String] = [:]
        var conditional: [String: String] = [:]
        for (key, value) in layer {
            if let bracket = key.firstIndex(of: "[") {
                let base = String(key[..<bracket])
                if conditional[base] == nil || key.contains("sdk=iphoneos") {
                    conditional[base] = value
                }
            } else {
                plain[key] = value
            }
        }
        for (key, value) in conditional where plain[key] == nil {
            plain[key] = value
        }
        return plain
    }

    public func raw(_ key: String) -> String? {
        values[key]
    }

    /// The expanded value of a setting, or nil when it is not set.
    public func value(_ key: String) -> String? {
        guard let raw = values[key] else { return nil }
        return expand(raw)
    }

    public func bool(_ key: String) -> Bool {
        guard let value = value(key)?.uppercased() else { return false }
        return value == "YES" || value == "TRUE" || value == "1"
    }

    /// Expands `$(VAR)` and `${VAR}` references. Undefined variables become
    /// empty strings, as they do in Xcode.
    public func expand(_ string: String) -> String {
        expandTracking(string).value
    }

    /// Expands references and reports which variables were undefined.
    public func expandTracking(_ string: String) -> (value: String, undefined: [String]) {
        var undefined: [String] = []
        let value = expand(string, depth: 0, undefined: &undefined)
        return (value, undefined)
    }

    private static let reference = TextPattern(#"\$\(([^()]+)\)|\$\{([^{}]+)\}"#)

    private func expand(_ string: String, depth: Int, undefined: inout [String]) -> String {
        guard depth < 10, string.contains("$") else { return string }
        var output = ""
        var cursor = string.startIndex
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        for match in BuildSettings.reference.expression.matches(in: string, options: [], range: range) {
            guard let matchRange = Range(match.range, in: string) else { continue }
            output += string[cursor..<matchRange.lowerBound]
            let groupIndex = match.range(at: 1).location != NSNotFound ? 1 : 2
            guard let nameRange = Range(match.range(at: groupIndex), in: string) else { continue }
            let expression = String(string[nameRange])
            let parts = expression.split(separator: ":").map(String.init)
            let name = parts.first ?? expression
            if let rawValue = values[name] {
                var value = expand(rawValue, depth: depth + 1, undefined: &undefined)
                for modifier in parts.dropFirst() {
                    value = BuildSettings.apply(modifier: modifier, to: value)
                }
                output += value
            } else {
                undefined.append(name)
            }
            cursor = matchRange.upperBound
        }
        output += string[cursor...]
        return output
    }

    private static func apply(modifier: String, to value: String) -> String {
        switch modifier {
        case "rfc1034identifier":
            return String(value.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "-" })
        case "c99extidentifier", "identifier":
            return String(value.map { $0.isLetter || $0.isNumber || $0 == "_" ? $0 : "_" })
        case "lower":
            return value.lowercased()
        case "upper":
            return value.uppercased()
        default:
            return value
        }
    }
}
