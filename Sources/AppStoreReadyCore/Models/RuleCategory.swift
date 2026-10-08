import Foundation

/// The area of the project a rule inspects.
public enum RuleCategory: String, Codable, CaseIterable, Sendable {
    case configuration
    case versioning
    case assets
    case privacy
    case security
    case buildSettings = "build-settings"
    case accessibility
    case project
}
