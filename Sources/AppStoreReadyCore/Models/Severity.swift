import Foundation

/// How serious a finding is.
///
/// Severities describe the *likely impact* of an issue on an App Store
/// submission. They are not claims about App Review outcomes: only
/// App Review can decide whether an app is accepted.
public enum Severity: String, Codable, CaseIterable, Sendable, Comparable {
    /// The check ran and found nothing to report.
    case pass = "PASS"
    /// Something looks wrong and should be reviewed before submission.
    case warning = "WARNING"
    /// A problem that is very likely to break the build upload or the app.
    case error = "ERROR"
    /// Neutral information about the scan.
    case info = "INFO"
    /// Something a static scan cannot decide; a person needs to check it.
    case manualReview = "MANUAL_REVIEW"

    /// Short label used in the terminal report.
    public var label: String {
        switch self {
        case .pass: return "PASS"
        case .warning: return "WARN"
        case .error: return "FAIL"
        case .info: return "INFO"
        case .manualReview: return "REVIEW"
        }
    }

    /// Ordering used for sorting reports: most serious first.
    var rank: Int {
        switch self {
        case .error: return 0
        case .warning: return 1
        case .manualReview: return 2
        case .info: return 3
        case .pass: return 4
        }
    }

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.rank < rhs.rank
    }
}
