import Foundation

/// ASR012: deployment targets that App Store Connect no longer accepts.
public struct DeploymentTargetRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR012",
        title: "Deployment target",
        description: "Compares each target's deployment target with Apple's current upload requirements: iOS and iPadOS apps must target iOS 13 or later, and the Xcode versions App Store Connect accepts support uploads only from iOS/iPadOS/tvOS 15, watchOS 8, macOS 11, and visionOS 1.",
        rationale: "Apple announced that since September 9, 2026, iOS and iPadOS apps uploaded to App Store Connect must target iOS 13 or later, and that since April 28, 2026, apps must be built with Xcode 26 or later. Apple's Xcode support page lists the deployment target range each Xcode version supports for uploading to App Store Connect. The SDK an app is built with cannot be checked from the project.",
        category: .buildConfiguration,
        references: [
            Reference("Upcoming requirements", "https://developer.apple.com/news/upcoming-requirements/"),
            Reference("Xcode support", "https://developer.apple.com/support/xcode/"),
        ]
    )

    struct Platform {
        let name: String
        let setting: String
        /// Lowest target App Store Connect accepts, when Apple states one.
        let uploadMinimum: [Int]?
        /// Lowest target Xcode 26 supports for App Store upload.
        let xcodeMinimum: [Int]
    }

    static func platform(for sdk: String) -> Platform? {
        switch sdk {
        case let s where s.hasPrefix("iphone"):
            return Platform(name: "iOS", setting: "IPHONEOS_DEPLOYMENT_TARGET", uploadMinimum: [13], xcodeMinimum: [15])
        case let s where s.hasPrefix("macosx"):
            return Platform(name: "macOS", setting: "MACOSX_DEPLOYMENT_TARGET", uploadMinimum: nil, xcodeMinimum: [11])
        case let s where s.hasPrefix("appletv"):
            return Platform(name: "tvOS", setting: "TVOS_DEPLOYMENT_TARGET", uploadMinimum: nil, xcodeMinimum: [15])
        case let s where s.hasPrefix("watch"):
            return Platform(name: "watchOS", setting: "WATCHOS_DEPLOYMENT_TARGET", uploadMinimum: nil, xcodeMinimum: [8])
        case let s where s.hasPrefix("xr"):
            return Platform(name: "visionOS", setting: "XROS_DEPLOYMENT_TARGET", uploadMinimum: nil, xcodeMinimum: [1])
        default:
            return nil
        }
    }

    static func parse(_ version: String) -> [Int]? {
        let parts = version.trimmingCharacters(in: .whitespaces).split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        return parts.compactMap { $0 }
    }

    static func isLower(_ a: [Int], than b: [Int]) -> Bool {
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x < y }
        }
        return false
    }

    public init() {}

    /// The platforms a target builds for. Multiplatform targets use
    /// `SDKROOT = auto` and list their platforms in SUPPORTED_PLATFORMS.
    static func platforms(for target: ResolvedTarget) -> [Platform] {
        if target.sdk == "auto" {
            let supported = (target.buildSettings.value("SUPPORTED_PLATFORMS") ?? "").split(separator: " ").map(String.init)
            var seen = Set<String>()
            return supported.compactMap(platform(for:)).filter { seen.insert($0.name).inserted }
        }
        return platform(for: target.sdk).map { [$0] } ?? []
    }

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.flatMap { target in
            Self.platforms(for: target).compactMap { evaluate(target, platform: $0, context: context) }
        }
    }

    private func evaluate(_ target: ResolvedTarget, platform: Platform, context: ScanContext) -> Finding? {
        guard let raw = target.buildSettings.value(platform.setting),
              let version = Self.parse(raw) else { return nil }
        let file = context.projectFile(for: target)
        let evidence = ["\(platform.setting) = \(raw) (\(target.configurationName))"]
        if let minimum = platform.uploadMinimum, Self.isLower(version, than: minimum) {
            return finding(
                "Deployment target below App Store minimum",
                message: "'\(target.name)' targets \(platform.name) \(raw). Apple requires iOS and iPadOS apps uploaded to App Store Connect since September 9, 2026 to target iOS 13 or later.",
                severity: .error,
                confidence: .high,
                classification: .verifiedIssue,
                file: file,
                target: target,
                evidence: evidence,
                fix: "Raise \(platform.setting) to at least \(platform.xcodeMinimum.map(String.init).joined(separator: ".")).0, the lowest target current Xcode versions support for App Store upload."
            )
        }
        if Self.isLower(version, than: platform.xcodeMinimum) {
            let minimum = platform.xcodeMinimum.map(String.init).joined(separator: ".")
            return finding(
                "Deployment target below Xcode's supported range",
                message: "'\(target.name)' targets \(platform.name) \(raw). Apple's Xcode support page lists \(platform.name) \(minimum) as the lowest deployment target Xcode 26 and later support for uploading to App Store Connect, and uploads must be built with Xcode 26 or later.",
                severity: .warning,
                confidence: .medium,
                classification: .potentialIssue,
                file: file,
                target: target,
                evidence: evidence,
                fix: "Raise \(platform.setting) to \(minimum) or later."
            )
        }
        return finding(
            "Deployment target is supported",
            message: "'\(target.name)' targets \(platform.name) \(raw), which current Xcode versions support for App Store upload.",
            severity: .pass,
            confidence: .high,
            file: file,
            target: target,
            evidence: evidence
        )
    }
}
