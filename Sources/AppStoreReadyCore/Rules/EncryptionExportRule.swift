import Foundation

/// ASR013: export compliance declaration in Info.plist.
public struct EncryptionExportRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR013",
        title: "Encryption export compliance",
        description: "Checks whether each app declares ITSAppUsesNonExemptEncryption in Info.plist.",
        rationale: "Without ITSAppUsesNonExemptEncryption in Info.plist, App Store Connect asks the export compliance questions every time you upload a new version. Declaring the key streamlines submission; the value must reflect the encryption the app and its libraries actually use.",
        category: .appStoreMetadata,
        references: [
            Reference("ITSAppUsesNonExemptEncryption", "https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption"),
            Reference("Complying with encryption export regulations", "https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations"),
            Reference("ITSEncryptionExportComplianceCode", "https://developer.apple.com/documentation/bundleresources/information-property-list/itsencryptionexportcompliancecode"),
        ]
    )

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.filter(\.productType.isApplication).compactMap { target in
            guard let info = target.infoPlist, !info.isUnreadable else { return nil }
            let file = context.infoPlistLocation(for: target, key: "ITSAppUsesNonExemptEncryption")
            guard let value = info.resolved["ITSAppUsesNonExemptEncryption"]?.boolValue else {
                return finding(
                    "Export compliance not declared in Info.plist",
                    message: "'\(target.name)' does not set ITSAppUsesNonExemptEncryption, so App Store Connect will ask the export compliance questions on every upload.",
                    severity: .info,
                    confidence: .high,
                    classification: .bestPractice,
                    file: file,
                    target: target,
                    fix: "Determine whether the app uses non-exempt encryption and set ITSAppUsesNonExemptEncryption (INFOPLIST_KEY_ITSAppUsesNonExemptEncryption) to YES or NO."
                )
            }
            if value {
                return finding(
                    "App declares non-exempt encryption",
                    message: "'\(target.name)' sets ITSAppUsesNonExemptEncryption to YES. Export compliance documentation may be required in App Store Connect.",
                    severity: .manualReview,
                    confidence: .high,
                    file: file,
                    target: target,
                    evidence: ["ITSAppUsesNonExemptEncryption = YES"] + (info.string("ITSEncryptionExportComplianceCode") == nil ? ["ITSEncryptionExportComplianceCode is not set"] : []),
                    fix: "Confirm the encryption classification, provide the export compliance documentation in App Store Connect, and add the ITSEncryptionExportComplianceCode it gives you to Info.plist."
                )
            }
            return finding(
                "Export compliance declared",
                message: "'\(target.name)' declares that it does not use non-exempt encryption.",
                severity: .pass,
                confidence: .high,
                file: file,
                target: target,
                evidence: ["ITSAppUsesNonExemptEncryption = NO"]
            )
        }
    }
}
