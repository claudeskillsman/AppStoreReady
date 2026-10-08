import Foundation

/// ASR020: SDKs on Apple's list of commonly used third-party SDKs.
public struct ThirdPartySDKRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR020",
        title: "Third-party SDK privacy manifests",
        description: "Matches dependencies from Package.resolved, Podfile.lock, Cartfile.resolved, and vendored frameworks against Apple's list of SDKs that require a privacy manifest and signature, and checks for a PrivacyInfo.xcprivacy where the SDK's files are available.",
        rationale: "Apple's documentation states that you must include the privacy manifest for any SDK on its list when you submit a new app, or an update that adds one of those SDKs, and that signatures are also required when the SDK is a binary dependency. Any version of a listed SDK, and SDKs that repackage them, are included.",
        category: .privacy,
        references: [
            Reference("Third-party SDK requirements", "https://developer.apple.com/support/third-party-SDK-requirements/"),
            Reference("Privacy manifest files", "https://developer.apple.com/documentation/bundleresources/privacy-manifest-files"),
        ]
    )

    /// Apple's list, as published at the reference URL (retrieved 2026-10-08).
    static let listedSDKs: [String] = [
        "Abseil", "AFNetworking", "Alamofire", "AppAuth", "BoringSSL / openssl_grpc", "Capacitor", "Charts",
        "connectivity_plus", "Cordova", "device_info_plus", "DKImagePickerController", "DKPhotoGallery",
        "FBAEMKit", "FBLPromises", "FBSDKCoreKit", "FBSDKCoreKit_Basics", "FBSDKLoginKit", "FBSDKShareKit",
        "file_picker", "FirebaseABTesting", "FirebaseAuth", "FirebaseCore", "FirebaseCoreDiagnostics",
        "FirebaseCoreExtension", "FirebaseCoreInternal", "FirebaseCrashlytics", "FirebaseDynamicLinks",
        "FirebaseFirestore", "FirebaseInstallations", "FirebaseMessaging", "FirebaseRemoteConfig", "Flutter",
        "flutter_inappwebview", "flutter_local_notifications", "fluttertoast", "FMDB", "geolocator_apple",
        "GoogleDataTransport", "GoogleSignIn", "GoogleToolboxForMac", "GoogleUtilities", "grpcpp", "GTMAppAuth",
        "GTMSessionFetcher", "hermes", "image_picker_ios", "IQKeyboardManager", "IQKeyboardManagerSwift",
        "Kingfisher", "leveldb", "Lottie", "MBProgressHUD", "nanopb", "OneSignal", "OneSignalCore",
        "OneSignalExtension", "OneSignalOutcomes", "OpenSSL", "OrderedSet", "package_info", "package_info_plus",
        "path_provider", "path_provider_ios", "Promises", "Protobuf", "Reachability", "RealmSwift", "RxCocoa",
        "RxRelay", "RxSwift", "SDWebImage", "share_plus", "shared_preferences_ios", "SnapKit", "sqflite",
        "Starscream", "SVProgressHUD", "SwiftyGif", "SwiftyJSON", "Toast", "UnityFramework", "url_launcher",
        "url_launcher_ios", "video_player_avfoundation", "wakelock", "webview_flutter_wkwebview",
    ]

    /// Swift package repository names that ship SDKs from the list.
    static let packageAliases: [String: String] = [
        "firebase-ios-sdk": "FirebaseCore",
        "googlesignin-ios": "GoogleSignIn",
        "facebook-ios-sdk": "FBSDKCoreKit",
        "lottie-ios": "Lottie",
        "lottie-spm": "Lottie",
        "realm-swift": "RealmSwift",
        "appauth-ios": "AppAuth",
        "gtm-session-fetcher": "GTMSessionFetcher",
        "gtmappauth": "GTMAppAuth",
        "googleutilities": "GoogleUtilities",
        "googledatatransport": "GoogleDataTransport",
        "abseil-cpp-binary": "Abseil",
        "grpc-binary": "grpcpp",
        "boringssl-swiftpm": "BoringSSL / openssl_grpc",
        "onesignal-ios-sdk": "OneSignal",
        "onesignal-xcframework": "OneSignal",
        "reachability.swift": "Reachability",
        "toast-swift": "Toast",
        "openssl-package": "OpenSSL",
        "dgcharts": "Charts",
        "iqkeyboardmanager": "IQKeyboardManagerSwift",
    ]

    static func listedName(for dependency: String) -> String? {
        let lowered = dependency.lowercased()
        if let alias = packageAliases[lowered] { return alias }
        return listedSDKs.first { $0.lowercased() == lowered || $0.lowercased().hasPrefix(lowered + " /") }
    }

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        guard context.targets.contains(where: { $0.productType.isApplication }) else { return [] }

        struct Match {
            let sdk: String
            let source: String
            let file: String
            let hasManifest: Bool?
        }
        var matches: [Match] = []
        for dependency in context.dependencies {
            guard let sdk = Self.listedName(for: dependency.name) else { continue }
            let version = dependency.version.map { " \($0)" } ?? ""
            matches.append(Match(sdk: sdk, source: "\(dependency.name)\(version) (\(dependency.manager.rawValue))", file: dependency.lockFile, hasManifest: dependency.hasPrivacyManifest))
        }

        // Frameworks committed to the repository.
        var vendored: [String: Bool] = [:]
        var frameworkFiles: [String: String] = [:]
        for path in context.allFilePaths {
            let components = path.split(separator: "/").map(String.init)
            guard let index = components.firstIndex(where: { $0.hasSuffix(".xcframework") || $0.hasSuffix(".framework") }) else { continue }
            let bundle = components[...index].joined(separator: "/")
            let name = (components[index] as NSString).deletingPathExtension
            guard Self.listedName(for: name) != nil else { continue }
            if components.last == "PrivacyInfo.xcprivacy" { vendored[bundle] = true } else if vendored[bundle] == nil { vendored[bundle] = false }
            frameworkFiles[bundle] = name
        }
        for (bundle, hasManifest) in vendored.sorted(by: { $0.key < $1.key }) {
            let name = frameworkFiles[bundle] ?? bundle
            matches.append(Match(sdk: Self.listedName(for: name) ?? name, source: "\(bundle) (vendored binary)", file: bundle, hasManifest: hasManifest))
        }

        guard !matches.isEmpty else {
            if context.dependencies.isEmpty { return [] }
            return [finding(
                "No listed third-party SDKs found",
                message: "None of the \(context.dependencies.count) dependencies in lock files are on Apple's list of SDKs that require a privacy manifest. SDKs added without a lock file were not checked.",
                severity: .pass,
                confidence: .medium
            )]
        }

        var findings: [Finding] = []
        let missing = matches.filter { $0.hasManifest == false }
        if !missing.isEmpty {
            findings.append(finding(
                "Listed SDK without a privacy manifest",
                message: "\(missing.count) SDK(s) on Apple's list were found without a PrivacyInfo.xcprivacy in their files. Versions released before Apple's requirement often do not include one.",
                severity: .warning,
                confidence: .medium,
                classification: .potentialIssue,
                file: missing[0].file,
                evidence: missing.map { "\($0.sdk): \($0.source) has no PrivacyInfo.xcprivacy" },
                fix: "Update these SDKs to a version that includes a privacy manifest (and a signature for binary SDKs), or replace them."
            ))
        }
        let unknown = matches.filter { $0.hasManifest == nil }
        if !unknown.isEmpty {
            findings.append(finding(
                "Listed SDKs need a privacy manifest check",
                message: "\(unknown.count) dependency(ies) are on Apple's list of SDKs that require a privacy manifest and signature. Their files are not in the scanned folder, so the manifest could not be checked.",
                severity: .manualReview,
                confidence: .medium,
                file: unknown[0].file,
                evidence: unknown.map { "\($0.sdk): \($0.source)" },
                fix: "Confirm that the version you use includes PrivacyInfo.xcprivacy (and is signed, if it is a binary). Xcode's privacy report (Product › Archive › Generate Privacy Report) lists the manifests it found."
            ))
        }
        if findings.isEmpty {
            findings.append(finding(
                "Listed SDKs include privacy manifests",
                message: "Every SDK on Apple's list that was found includes a PrivacyInfo.xcprivacy. Signatures of binary SDKs were not checked.",
                severity: .pass,
                confidence: .medium,
                file: matches[0].file,
                evidence: matches.map { "\($0.sdk): \($0.source) includes a privacy manifest" }
            ))
        }
        return findings
    }
}
