import Foundation

/// A documentation source that supports a rule.
public struct Reference: Codable, Equatable, Sendable {
    public let title: String
    public let url: URL

    public init(_ title: String, _ url: String) {
        self.title = title
        // References are compile-time constants.
        self.url = URL(string: url)!
    }
}

/// Static description of a rule, shared by every finding it produces.
public struct RuleMetadata: Codable, Equatable, Sendable {
    /// Stable identifier, for example `ASR001`. Never reuse an identifier.
    public let id: String
    /// Short human readable name.
    public let title: String
    /// What the rule checks.
    public let description: String
    /// Why the problem matters for a submission.
    public let rationale: String
    public let category: RuleCategory
    /// Sources that back the rule, most important first. Apple documentation
    /// wherever a statement depends on Apple's requirements.
    public let references: [Reference]

    /// Primary reference documentation.
    public var documentationURL: URL? { references.first?.url }

    public init(id: String, title: String, description: String, rationale: String, category: RuleCategory, references: [Reference]) {
        self.id = id
        self.title = title
        self.description = description
        self.rationale = rationale
        self.category = category
        self.references = references
    }
}
