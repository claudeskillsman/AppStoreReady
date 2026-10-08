import Foundation

/// Xcode product types that AppStoreReady distinguishes.
public enum ProductType: Equatable, Sendable {
    case application
    case appExtension
    case watchApp
    case appClip
    case framework
    case staticLibrary
    case bundle
    case unitTest
    case uiTest
    case commandLineTool
    case other(String)

    public init(identifier: String) {
        switch identifier {
        case "com.apple.product-type.application",
             "com.apple.product-type.application.messages":
            self = .application
        case "com.apple.product-type.application.on-demand-install-capable":
            self = .appClip
        case "com.apple.product-type.application.watchapp",
             "com.apple.product-type.application.watchapp2",
             "com.apple.product-type.application.watchapp2-container":
            self = .watchApp
        case let id where id.hasPrefix("com.apple.product-type.app-extension")
            || id.hasPrefix("com.apple.product-type.extensionkit-extension")
            || id.hasPrefix("com.apple.product-type.watchkit2-extension")
            || id == "com.apple.product-type.tv-app-extension":
            self = .appExtension
        case "com.apple.product-type.framework", "com.apple.product-type.framework.static":
            self = .framework
        case "com.apple.product-type.library.static", "com.apple.product-type.library.dynamic":
            self = .staticLibrary
        case "com.apple.product-type.bundle":
            self = .bundle
        case "com.apple.product-type.bundle.unit-test":
            self = .unitTest
        case "com.apple.product-type.bundle.ui-testing":
            self = .uiTest
        case "com.apple.product-type.tool":
            self = .commandLineTool
        default:
            self = .other(identifier)
        }
    }

    /// Products that are submitted to the App Store as, or inside, an app.
    public var isDistributableBundle: Bool {
        switch self {
        case .application, .appExtension, .watchApp, .appClip: return true
        default: return false
        }
    }

    /// Top level app products (which need an app icon of their own).
    public var isApplication: Bool {
        switch self {
        case .application, .watchApp, .appClip: return true
        default: return false
        }
    }

    public var displayName: String {
        switch self {
        case .application: return "application"
        case .appExtension: return "app extension"
        case .watchApp: return "watchOS app"
        case .appClip: return "App Clip"
        case .framework: return "framework"
        case .staticLibrary: return "library"
        case .bundle: return "bundle"
        case .unitTest: return "unit test bundle"
        case .uiTest: return "UI test bundle"
        case .commandLineTool: return "command line tool"
        case .other(let id): return id
        }
    }
}

/// One `XCBuildConfiguration` as written in the project file, before layering.
public struct RawBuildConfiguration: Sendable {
    public let name: String
    public let settings: [String: String]
    /// The `.xcconfig` file this configuration is based on, if any.
    public let baseConfigurationFile: URL?
}

/// A native target from a `project.pbxproj` file.
public struct ProjectTarget: Sendable {
    public let id: String
    public let name: String
    public let productType: ProductType
    public let configurations: [RawBuildConfiguration]
    public let defaultConfigurationName: String?
    /// Files that are members of the target (sources and resources), standardized paths.
    public let memberFiles: Set<String>
    /// Folders whose entire contents belong to the target
    /// (synchronized groups, folder references, asset catalogs).
    public let memberDirectories: [String]
    /// Files explicitly excluded from synchronized folders.
    public let excludedFiles: Set<String>

    /// Whether AppStoreReady could work out which files belong to the target.
    public var hasKnownMembership: Bool {
        !memberFiles.isEmpty || !memberDirectories.isEmpty
    }

    public func contains(path: String) -> Bool {
        if excludedFiles.contains(path) { return false }
        if memberFiles.contains(path) { return true }
        return memberDirectories.contains { path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }
}

/// A parsed `.xcodeproj`.
public struct XcodeProject: Sendable {
    /// URL of the `.xcodeproj` bundle.
    public let url: URL
    /// `SRCROOT`: the directory that contains the `.xcodeproj` (plus `projectDirPath`).
    public let sourceRoot: URL
    public let name: String
    public let projectConfigurations: [RawBuildConfiguration]
    public let defaultConfigurationName: String?
    public let targets: [ProjectTarget]
    public let schemes: [Scheme]

    public var configurationNames: [String] {
        projectConfigurations.map(\.name)
    }
}

/// A scheme from `xcshareddata/xcschemes` or `xcuserdata`.
public struct Scheme: Sendable {
    public let name: String
    public let url: URL
    public let isShared: Bool
    public let archiveConfiguration: String?
    public let launchConfiguration: String?
    /// `BlueprintIdentifier`s of targets built by the scheme.
    public let buildableTargetIDs: [String]
    public let buildableTargetNames: [String]
}
