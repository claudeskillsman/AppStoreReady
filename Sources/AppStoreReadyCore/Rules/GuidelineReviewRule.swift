import Foundation

/// ASR025: App Review Guideline topics that the code suggests are relevant.
///
/// Every finding is MANUAL_REVIEW: static analysis can show that a topic
/// applies, never that the app complies with it.
public struct GuidelineReviewRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR025",
        title: "App Review Guideline topics",
        description: "Flags App Review Guideline topics that apply because of what the code uses: in-app purchases (3.1.1), third-party sign-in (4.8), and account creation (5.1.1(v)). Also lists Run Script build phases, which AppStoreReady does not analyze.",
        rationale: "These guidelines are evaluated by App Review on the running app and its metadata. The code shows that they apply; only a person can check that the app meets them.",
        category: .manualReview,
        references: [
            Reference("App Review Guidelines", "https://developer.apple.com/app-store/review/guidelines/"),
            Reference("Guideline 3.1.1 In-App Purchase", "https://developer.apple.com/app-store/review/guidelines/#in-app-purchase"),
            Reference("Guideline 4.8 Login Services", "https://developer.apple.com/app-store/review/guidelines/#login-services"),
            Reference("Guideline 5.1.1 Data Collection and Storage", "https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage"),
        ]
    )

    struct Topic {
        let title: String
        let guideline: String
        let message: String
        let patterns: [TextPattern]
        let dependencies: [String]
        let anchor: String
    }

    static let topics: [Topic] = [
        Topic(
            title: "In-app purchase rules apply",
            guideline: "3.1.1",
            message: "The code uses StoreKit purchase APIs or an in-app purchase SDK. Guideline 3.1.1 says that unlocking features or functionality within the app must use in-app purchase, and that apps may not use their own unlock mechanisms such as license keys or QR codes.",
            // Purchase APIs only: `import StoreKit` alone is also used for review prompts.
            patterns: [TextPattern(#"\bSKPaymentQueue\b|\bSKProductsRequest\b|\bProduct\.products\s*\(|\bTransaction\.(updates|currentEntitlements)\b|\b(SubscriptionStoreView|ProductView|StoreView)\s*\("#)],
            dependencies: ["purchases-ios", "RevenueCat", "SwiftyStoreKit", "Qonversion", "adapty"],
            anchor: "in-app-purchase"
        ),
        Topic(
            title: "Third-party sign-in requires an equivalent option",
            guideline: "4.8",
            message: "The code uses a third-party sign-in SDK. Guideline 4.8 says apps that use a third-party or social login service for the user's primary account must also offer an equivalent login option that limits data collection to name and email, lets people keep their email private, and does not track without consent. The guideline lists exemptions.",
            patterns: [TextPattern(#"\bGIDSignIn\b|\bFBSDKLoginManager\b|\bLoginManager\s*\(\s*\)\s*\.\s*logIn\b|\bFBLoginButton\b|\bimport\s+(FacebookLogin|FBSDKLoginKit|GoogleSignIn)\b"#)],
            dependencies: ["GoogleSignIn", "GoogleSignIn-iOS", "FBSDKLoginKit", "facebook-ios-sdk", "FacebookLogin", "LineSDK", "TwitterKit"],
            anchor: "login-services"
        ),
        Topic(
            title: "Account deletion must be offered",
            guideline: "5.1.1(v)",
            message: "The code appears to create user accounts. Guideline 5.1.1(v) says that if your app supports account creation, you must also offer account deletion within the app.",
            patterns: [TextPattern(#"createUser\(withEmail|\bsignUp\s*\(|\bcreateAccount\s*\(|\bregisterUser\s*\(|"(Sign Up|Create Account|Create an account|Register)""#)],
            dependencies: [],
            anchor: "data-collection-and-storage"
        ),
    ]

    static let signInWithApple = [TextPattern(#"\bASAuthorizationAppleIDProvider\b|\bSignInWithAppleButton\b"#)]

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        let apps = context.targets.filter(\.productType.isApplication)
        guard !apps.isEmpty else { return [] }
        var findings: [Finding] = []
        let codeFiles = context.files.filter { $0.isCode && !isTestPath($0.relativePath) }
        let dependencyNames = Set(context.dependencies.map { $0.name.lowercased() })

        for topic in Self.topics {
            var evidence: [String] = []
            var location: (file: String, line: Int)?
            if let match = context.firstMatch(of: topic.patterns, in: codeFiles) {
                evidence.append("\(match.file.relativePath):\(match.line)")
                location = (match.file.relativePath, match.line)
            }
            for dependency in topic.dependencies where dependencyNames.contains(dependency.lowercased()) {
                evidence.append("Dependency: \(dependency)")
            }
            guard !evidence.isEmpty else { continue }
            if topic.guideline == "4.8", let apple = context.firstMatch(of: Self.signInWithApple, in: codeFiles) {
                evidence.append("Sign in with Apple found at \(apple.file.relativePath):\(apple.line); check that it is offered as an equivalent option")
            }
            findings.append(finding(
                "\(topic.title) (Guideline \(topic.guideline))",
                message: topic.message,
                severity: .manualReview,
                confidence: .medium,
                file: location?.file,
                line: location?.line,
                evidence: evidence,
                fix: "Review Guideline \(topic.guideline) and confirm the app follows it before submitting.",
                documentation: "https://developer.apple.com/app-store/review/guidelines/#\(topic.anchor)"
            ))
        }

        for target in context.targets where !target.target.scriptPhaseNames.isEmpty {
            findings.append(finding(
                "Build phase scripts were not analyzed",
                message: "'\(target.name)' runs \(target.target.scriptPhaseNames.count) script build phase(s). AppStoreReady never executes scripts, so anything they generate or modify was not checked.",
                severity: .manualReview,
                confidence: .high,
                file: context.projectFile(for: target),
                target: target,
                evidence: target.target.scriptPhaseNames.map { "Run Script phase: \($0)" },
                fix: "Review what these scripts add to the app (for example generated plists, keys, or downloaded files)."
            ))
        }
        return findings
    }
}
