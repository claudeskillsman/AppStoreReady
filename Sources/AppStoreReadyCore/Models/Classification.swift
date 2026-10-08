import Foundation

/// What kind of statement a finding makes.
///
/// Severity says how much a finding matters; classification says how
/// certain the underlying claim is. AppStoreReady never claims to verify
/// App Review outcomes, accessibility compliance, the correctness of
/// privacy disclosures, or full guideline compliance.
public enum Classification: String, Codable, CaseIterable, Sendable {
    /// Read directly from project configuration and contradicts documented behavior.
    case verifiedIssue = "verified-issue"
    /// Inferred from source patterns or incomplete information; may be a false positive.
    case potentialIssue = "potential-issue"
    /// Not a documented requirement, but commonly recommended.
    case bestPractice = "best-practice"
    /// Cannot be decided by static analysis.
    case manualReview = "manual-review"

    public var displayName: String {
        switch self {
        case .verifiedIssue: return "Verified configuration issue"
        case .potentialIssue: return "Potential issue"
        case .bestPractice: return "Best-practice recommendation"
        case .manualReview: return "Requires manual review"
        }
    }

    /// The default classification for a severity and confidence.
    public static func `default`(for severity: Severity, confidence: Confidence) -> Classification? {
        switch severity {
        case .pass: return nil
        case .error, .warning: return confidence == .high ? .verifiedIssue : .potentialIssue
        case .info: return .bestPractice
        case .manualReview: return .manualReview
        }
    }
}
