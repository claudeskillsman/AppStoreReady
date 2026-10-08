import Foundation

/// A single result produced by a rule.
///
/// `evidence` must never contain secret values. Rules that look at
/// sensitive content are responsible for redacting it (see `Redactor`).
public struct Finding: Codable, Equatable, Sendable {
    public let ruleID: String
    public let title: String
    public let message: String
    public let severity: Severity
    /// Nil for passing checks.
    public let classification: Classification?
    public let category: RuleCategory
    public let confidence: Confidence
    /// Path of the relevant file, relative to the scan root when possible.
    public let file: String?
    public let line: Int?
    /// The target the finding applies to, if any.
    public let target: String?
    /// Build configuration that was inspected, if relevant.
    public let configuration: String?
    public let evidence: [String]
    /// Why the problem matters for a submission.
    public let whyItMatters: String?
    public let suggestedFix: String?
    public let documentationURL: URL?

    public init(
        ruleID: String,
        title: String,
        message: String,
        severity: Severity,
        classification: Classification? = nil,
        category: RuleCategory,
        confidence: Confidence,
        file: String? = nil,
        line: Int? = nil,
        target: String? = nil,
        configuration: String? = nil,
        evidence: [String] = [],
        whyItMatters: String? = nil,
        suggestedFix: String? = nil,
        documentationURL: URL? = nil
    ) {
        self.ruleID = ruleID
        self.title = title
        self.message = message
        self.severity = severity
        self.classification = classification ?? Classification.default(for: severity, confidence: confidence)
        self.category = category
        self.confidence = confidence
        self.file = file
        self.line = line
        self.target = target
        self.configuration = configuration
        self.evidence = evidence
        self.whyItMatters = whyItMatters
        self.suggestedFix = suggestedFix
        self.documentationURL = documentationURL
    }
}
