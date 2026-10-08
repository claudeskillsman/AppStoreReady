import Foundation

/// How sure AppStoreReady is about a finding.
///
/// Static analysis cannot see everything (generated code, binary SDKs,
/// build scripts), so every finding states its confidence explicitly.
public enum Confidence: String, Codable, CaseIterable, Sendable {
    /// Read directly from a configuration value.
    case high
    /// Inferred from source patterns or partial configuration.
    case medium
    /// A heuristic; expect false positives.
    case low
}
