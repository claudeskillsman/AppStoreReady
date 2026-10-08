import Foundation

/// Produces safe descriptions of sensitive values.
///
/// Reports must never contain a detected secret, not even partially,
/// so redacted output only describes the *shape* of the value.
public enum Redactor {
    public static func describe(_ value: String) -> String {
        "[REDACTED: \(value.count) characters]"
    }

    /// Shannon entropy in bits per character.
    public static func entropy(_ value: String) -> Double {
        guard !value.isEmpty else { return 0 }
        var counts: [Character: Int] = [:]
        for character in value {
            counts[character, default: 0] += 1
        }
        let length = Double(value.count)
        return counts.values.reduce(0) { total, count in
            let probability = Double(count) / length
            return total - probability * log2(probability)
        }
    }
}
