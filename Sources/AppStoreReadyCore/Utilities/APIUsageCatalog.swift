import Foundation

/// A protected resource that needs a purpose string in Info.plist.
struct ProtectedResource {
    let name: String
    /// Any of these keys satisfies the requirement.
    let keys: [String]
    /// Calls that request access (or trigger the system prompt).
    let strongPatterns: [TextPattern]
    /// Type names that suggest, but do not prove, access.
    let weakPatterns: [TextPattern]
}

/// A category of "required reason" APIs that must be declared in a privacy manifest.
struct RequiredReasonCategory {
    let name: String
    /// The `NSPrivacyAccessedAPIType` value.
    let identifier: String
    /// Approved reason codes for this category.
    let reasons: Set<String>
    /// Reason codes Apple reserves for third-party SDKs.
    let sdkOnlyReasons: Set<String>
    let patterns: [TextPattern]
}

/// Source patterns AppStoreReady uses to detect API usage.
///
/// Detection is textual, so it cannot see APIs used by binary SDKs or
/// generated code, and it can be fooled by identically named symbols.
enum APIUsageCatalog {
    static let protectedResources: [ProtectedResource] = [
        ProtectedResource(
            name: "Camera",
            keys: ["NSCameraUsageDescription"],
            strongPatterns: [
                TextPattern(#"AVCaptureDevice\s*\.\s*requestAccess\s*\(\s*for\s*:\s*\.video"#),
                TextPattern(#"requestAccessForMediaType\s*:\s*AVMediaTypeVideo"#),
                TextPattern(#"sourceType\s*=\s*\.camera\b"#),
                TextPattern(#"UIImagePickerControllerSourceTypeCamera"#),
            ],
            weakPatterns: [
                TextPattern(#"\bAVCaptureSession\b"#),
                TextPattern(#"\bDataScannerViewController\b"#),
            ]
        ),
        ProtectedResource(
            name: "Microphone",
            keys: ["NSMicrophoneUsageDescription"],
            strongPatterns: [
                TextPattern(#"\brequestRecordPermission\b"#),
                TextPattern(#"AVCaptureDevice\s*\.\s*requestAccess\s*\(\s*for\s*:\s*\.audio"#),
                TextPattern(#"requestAccessForMediaType\s*:\s*AVMediaTypeAudio"#),
            ],
            weakPatterns: [
                TextPattern(#"\bAVAudioRecorder\b"#),
            ]
        ),
        ProtectedResource(
            name: "Speech recognition",
            keys: ["NSSpeechRecognitionUsageDescription"],
            strongPatterns: [TextPattern(#"SFSpeechRecognizer\s*\.\s*requestAuthorization|\[SFSpeechRecognizer\s+requestAuthorization"#)],
            weakPatterns: [TextPattern(#"\bSFSpeechRecognizer\b"#)]
        ),
        ProtectedResource(
            name: "Photo library",
            keys: ["NSPhotoLibraryUsageDescription"],
            strongPatterns: [
                TextPattern(#"PHPhotoLibrary\s*\.\s*requestAuthorization\s*(?!\(\s*for\s*:\s*\.addOnly)"#),
                TextPattern(#"\[PHPhotoLibrary\s+requestAuthorization"#),
                TextPattern(#"PHAsset\s*\.\s*fetchAssets"#),
            ],
            weakPatterns: [TextPattern(#"\bPHPhotoLibrary\s*\.\s*shared\s*\(\s*\)"#)]
        ),
        ProtectedResource(
            name: "Saving to the photo library",
            keys: ["NSPhotoLibraryAddUsageDescription", "NSPhotoLibraryUsageDescription"],
            strongPatterns: [
                TextPattern(#"\bUIImageWriteToSavedPhotosAlbum\s*\("#),
                TextPattern(#"\bUISaveVideoAtPathToSavedPhotosAlbum\s*\("#),
                TextPattern(#"requestAuthorization\s*\(\s*for\s*:\s*\.addOnly"#),
            ],
            weakPatterns: [TextPattern(#"\bPHAssetChangeRequest\b"#)]
        ),
        ProtectedResource(
            name: "Location (when in use)",
            keys: ["NSLocationWhenInUseUsageDescription"],
            strongPatterns: [
                TextPattern(#"\brequestWhenInUseAuthorization\b"#),
                TextPattern(#"\brequestAlwaysAuthorization\b"#),
            ],
            weakPatterns: [
                TextPattern(#"\bstartUpdatingLocation\b"#),
                TextPattern(#"\brequestLocation\s*\(\s*\)"#),
            ]
        ),
        ProtectedResource(
            name: "Location (always)",
            keys: ["NSLocationAlwaysAndWhenInUseUsageDescription"],
            strongPatterns: [TextPattern(#"\brequestAlwaysAuthorization\b"#)],
            weakPatterns: []
        ),
        ProtectedResource(
            name: "Contacts",
            keys: ["NSContactsUsageDescription"],
            strongPatterns: [
                TextPattern(#"requestAccess\s*\(\s*for\s*:\s*\.contacts"#),
                TextPattern(#"requestAccessForEntityType\s*:\s*CNEntityTypeContacts"#),
            ],
            weakPatterns: [TextPattern(#"\bCNContactStore\s*\(\s*\)"#)]
        ),
        ProtectedResource(
            name: "Calendars",
            keys: ["NSCalendarsUsageDescription", "NSCalendarsFullAccessUsageDescription", "NSCalendarsWriteOnlyAccessUsageDescription"],
            strongPatterns: [
                TextPattern(#"\brequestFullAccessToEvents\b"#),
                TextPattern(#"\brequestWriteOnlyAccessToEvents\b"#),
                TextPattern(#"requestAccess\s*\(\s*to\s*:\s*\.event\b"#),
            ],
            weakPatterns: [TextPattern(#"\bEKEventStore\s*\(\s*\)"#)]
        ),
        ProtectedResource(
            name: "Reminders",
            keys: ["NSRemindersUsageDescription", "NSRemindersFullAccessUsageDescription"],
            strongPatterns: [
                TextPattern(#"\brequestFullAccessToReminders\b"#),
                TextPattern(#"requestAccess\s*\(\s*to\s*:\s*\.reminder\b"#),
            ],
            weakPatterns: []
        ),
        ProtectedResource(
            name: "Bluetooth",
            keys: ["NSBluetoothAlwaysUsageDescription"],
            strongPatterns: [
                TextPattern(#"\bCBCentralManager\s*\("#),
                TextPattern(#"\bCBPeripheralManager\s*\("#),
                TextPattern(#"\[\s*\[\s*CB(Central|Peripheral)Manager\s+alloc\s*\]"#),
            ],
            weakPatterns: []
        ),
        ProtectedResource(
            name: "Health data",
            keys: ["NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"],
            strongPatterns: [TextPattern(#"requestAuthorization\s*\(\s*toShare"#)],
            weakPatterns: [TextPattern(#"\bHKHealthStore\s*\(\s*\)"#)]
        ),
        ProtectedResource(
            name: "Motion and fitness",
            keys: ["NSMotionUsageDescription"],
            strongPatterns: [
                TextPattern(#"\bCMMotionActivityManager\s*\("#),
                TextPattern(#"\bCMPedometer\s*\("#),
            ],
            weakPatterns: []
        ),
        ProtectedResource(
            name: "App tracking",
            keys: ["NSUserTrackingUsageDescription"],
            strongPatterns: [TextPattern(#"ATTrackingManager\s*\.\s*requestTrackingAuthorization|\[ATTrackingManager\s+requestTrackingAuthorization"#)],
            weakPatterns: []
        ),
        ProtectedResource(
            name: "Face ID",
            keys: ["NSFaceIDUsageDescription"],
            strongPatterns: [TextPattern(#"\.deviceOwnerAuthenticationWithBiometrics\b|LAPolicyDeviceOwnerAuthenticationWithBiometrics"#)],
            weakPatterns: [TextPattern(#"\bevaluatePolicy\s*\("#)]
        ),
        ProtectedResource(
            name: "Media library",
            keys: ["NSAppleMusicUsageDescription"],
            strongPatterns: [
                TextPattern(#"MPMediaLibrary\s*\.\s*requestAuthorization"#),
                TextPattern(#"MusicAuthorization\s*\.\s*request\s*\("#),
            ],
            weakPatterns: [TextPattern(#"\bMPMediaQuery\b"#)]
        ),
        ProtectedResource(
            name: "NFC",
            keys: ["NFCReaderUsageDescription"],
            strongPatterns: [TextPattern(#"\bNFC(NDEF|Tag)ReaderSession\s*\("#)],
            weakPatterns: []
        ),
        ProtectedResource(
            name: "HomeKit",
            keys: ["NSHomeKitUsageDescription"],
            strongPatterns: [TextPattern(#"\bHMHomeManager\s*\("#)],
            weakPatterns: []
        ),
        ProtectedResource(
            name: "Local network",
            keys: ["NSLocalNetworkUsageDescription"],
            strongPatterns: [],
            weakPatterns: [TextPattern(#"\bNWBrowser\s*\(|\bNetServiceBrowser\s*\(|\bNSNetServiceBrowser\b"#)]
        ),
    ]

    /// Categories and reason codes from Apple's "Describing use of required reason API"
    /// and the NSPrivacyAccessedAPIType reference (retrieved 2026-10-08).
    static let requiredReasonCategories: [RequiredReasonCategory] = [
        RequiredReasonCategory(
            name: "File timestamp APIs",
            identifier: "NSPrivacyAccessedAPICategoryFileTimestamp",
            reasons: ["DDA9.1", "C617.1", "3B52.1", "0A2A.1"],
            sdkOnlyReasons: ["0A2A.1"],
            patterns: [
                TextPattern(#"FileAttributeKey\s*\.\s*(creationDate|modificationDate)\b"#),
                TextPattern(#"\[\s*\.(creationDate|modificationDate)\s*\]"#),
                TextPattern(#"\bfileModificationDate\s*\("#),
                TextPattern(#"\.(contentModificationDateKey|creationDateKey)\b"#),
                TextPattern(#"\bNSFile(Creation|Modification)Date\b"#),
                TextPattern(#"\bNSURL(ContentModificationDate|CreationDate)Key\b"#),
                TextPattern(#"\b(getattrlist|getattrlistbulk|fgetattrlist|getattrlistat|stat|fstat|fstatat|lstat)\s*\("#),
            ]
        ),
        RequiredReasonCategory(
            name: "System boot time APIs",
            identifier: "NSPrivacyAccessedAPICategorySystemBootTime",
            reasons: ["35F9.1", "8FFB.1", "3D61.1"],
            sdkOnlyReasons: [],
            patterns: [
                TextPattern(#"\.systemUptime\b"#),
                TextPattern(#"\bmach_absolute_time\s*\("#),
            ]
        ),
        RequiredReasonCategory(
            name: "Disk space APIs",
            identifier: "NSPrivacyAccessedAPICategoryDiskSpace",
            reasons: ["85F4.1", "E174.1", "7D9E.1", "B728.1"],
            sdkOnlyReasons: [],
            patterns: [
                TextPattern(#"volumeAvailableCapacity(ForImportantUsage|ForOpportunisticUsage)?Key\b"#),
                TextPattern(#"\bvolumeTotalCapacityKey\b"#),
                TextPattern(#"FileAttributeKey\s*\.\s*(systemFreeSize|systemSize)\b"#),
                TextPattern(#"\[\s*\.(systemFreeSize|systemSize)\s*\]"#),
                TextPattern(#"\bNSFileSystem(Free)?Size\b"#),
                TextPattern(#"\b(statfs|statvfs|fstatfs|fstatvfs)\s*\("#),
            ]
        ),
        RequiredReasonCategory(
            name: "Active keyboard APIs",
            identifier: "NSPrivacyAccessedAPICategoryActiveKeyboards",
            reasons: ["3EC4.1", "54BD.1"],
            sdkOnlyReasons: [],
            patterns: [TextPattern(#"\bactiveInputModes\b"#)]
        ),
        RequiredReasonCategory(
            name: "User defaults APIs",
            identifier: "NSPrivacyAccessedAPICategoryUserDefaults",
            reasons: ["CA92.1", "1C8F.1", "C56D.1", "AC6B.1"],
            sdkOnlyReasons: ["C56D.1"],
            patterns: [
                TextPattern(#"\bUserDefaults\b"#),
                TextPattern(#"\bNSUserDefaults\b"#),
                TextPattern(#"@AppStorage\b"#),
            ]
        ),
    ]

    /// Values Apple documents for `NSPrivacyCollectedDataType` (retrieved 2026-10-08).
    /// Apple spells PhotosorVideos with a lowercase "or".
    static let collectedDataTypes: Set<String> = Set([
        "Name", "EmailAddress", "PhoneNumber", "PhysicalAddress", "OtherUserContactInfo",
        "Health", "Fitness", "PaymentInfo", "CreditInfo", "OtherFinancialInfo",
        "PreciseLocation", "CoarseLocation", "SensitiveInfo", "Contacts", "EmailsOrTextMessages",
        "PhotosorVideos", "AudioData", "GameplayContent", "CustomerSupport", "OtherUserContent",
        "BrowsingHistory", "SearchHistory", "UserID", "DeviceID", "PurchaseHistory",
        "ProductInteraction", "AdvertisingData", "OtherUsageData", "CrashData", "PerformanceData",
        "OtherDiagnosticData", "EnvironmentScanning", "Hands", "Head", "OtherDataTypes",
    ].map { "NSPrivacyCollectedDataType" + $0 })

    /// Values Apple documents for `NSPrivacyCollectedDataTypePurposes`.
    static let collectedDataPurposes: Set<String> = Set([
        "ThirdPartyAdvertising", "DeveloperAdvertising", "Analytics",
        "ProductPersonalization", "AppFunctionality", "Other",
    ].map { "NSPrivacyCollectedDataTypePurpose" + $0 })

    /// Code that uses App Tracking Transparency or the advertising identifier.
    static let trackingPatterns = [TextPattern(#"\bATTrackingManager\b|\badvertisingIdentifier\b|\bASIdentifierManager\b"#)]
}
