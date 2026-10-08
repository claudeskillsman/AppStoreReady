import Foundation

/// Static description of a rule, shared by every finding it produces.
public struct RuleMetadata: Codable, Equatable, Sendable {
    /// Stable identifier, for example `ASR001`. Never reuse an identifier.
    public let id: String
    /// Short human readable name.
    public let title: String
    /// What the rule checks and why it matters.
    public let description: String
    public let category: RuleCategory
    /// Primary reference documentation, preferably from Apple.
    public let documentationURL: URL?

    public init(id: String, title: String, description: String, category: RuleCategory, documentationURL: URL?) {
        self.id = id
        self.title = title
        self.description = description
        self.category = category
        self.documentationURL = documentationURL
    }
}
