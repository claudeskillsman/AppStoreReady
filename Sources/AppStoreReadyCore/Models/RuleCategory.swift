import Foundation

/// The area of the project a rule inspects.
public enum RuleCategory: String, Codable, CaseIterable, Sendable {
    case appConfiguration = "app-configuration"
    case privacy
    case security
    case permissions
    case signing
    case assets
    case buildConfiguration = "build-configuration"
    case accessibility
    case appStoreMetadata = "app-store-metadata"
    case manualReview = "manual-review"

    public var displayName: String {
        switch self {
        case .appConfiguration: return "App Configuration"
        case .privacy: return "Privacy"
        case .security: return "Security"
        case .permissions: return "Permissions"
        case .signing: return "Signing"
        case .assets: return "Assets"
        case .buildConfiguration: return "Build Configuration"
        case .accessibility: return "Accessibility"
        case .appStoreMetadata: return "App Store Metadata"
        case .manualReview: return "Manual Review"
        }
    }
}
