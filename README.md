# AppStoreReady

AppStoreReady is an open-source command-line tool that audits an Xcode project for likely App Store submission problems before you upload a build. It runs 25 checks in ten categories, from bundle identifiers, launch screens, and deployment targets to privacy manifests, third-party SDKs, App Transport Security, entitlements, signing, app icons, and hardcoded secrets. Every check links to the Apple documentation it is based on.

Example output (abridged):

```
$ appstoreready scan ./MyApp

AppStoreReady — iOS App Audit

Scanned ./MyApp
  Project: MyApp.xcodeproj
  Target:  MyApp (Release)

PASS    Bundle identifier configured  [MyApp]
FAIL    Missing launch screen  [MyApp]
        'MyApp' declares neither UILaunchStoryboardName nor UILaunchScreen.
        File: MyApp/Info.plist
        Why: Apple's documentation states that every iOS app must provide a launch screen, which the system shows while the app launches.
        Fix: Add a launch screen: set Launch Screen File in the target's General settings, or add a UILaunchScreen dictionary to Info.plist ...
        Rule ASR011 · Verified configuration issue · confidence high · https://developer.apple.com/documentation/xcode/specifying-your-apps-launch-screen
FAIL    Background task identifier not permitted  [MyApp]
        'MyApp' registers background task identifiers that are not in BGTaskSchedulerPermittedIdentifiers. ...
        File: MyApp/Background.swift:5
        • MyApp/Background.swift:5 registers 'com.acme.myapp.refresh'
        Why: BGTaskScheduler refuses to register identifiers that are not listed in BGTaskSchedulerPermittedIdentifiers, ...
        Fix: Add each identifier to BGTaskSchedulerPermittedIdentifiers in Info.plist.
        Rule ASR019 · Verified configuration issue · confidence high · https://developer.apple.com/documentation/bundleresources/information-property-list/bgtaskschedulerpermittedidentifiers
REVIEW  In-app purchase rules apply (Guideline 3.1.1)
        The code uses StoreKit or an in-app purchase SDK. Guideline 3.1.1 says that unlocking features or functionality within the app must use in-app purchase, ...
        File: MyApp/Store.swift:1
        Fix: Review Guideline 3.1.1 and confirm the app follows it before submitting.
        Rule ASR025 · Requires manual review · confidence medium · https://developer.apple.com/app-store/review/guidelines/#in-app-purchase

Summary: 2 failures, 0 warnings, 0 recommendations, 1 manual review item.
1 check passed.
AppStoreReady reports likely problems found by static analysis. It cannot predict App Review decisions.
```

AppStoreReady is a static analyser. It points out things that are likely to break an upload, crash the app, or draw attention in review, and it says how sure it is about each one. It does not and cannot verify App Review approval, full guideline compliance, real accessibility, or whether your privacy disclosures are correct; where those topics apply, it asks for a manual review instead.

## Installation

AppStoreReady is a Swift package. It needs Swift 5.9 or later (Xcode 15+ on macOS, or a Swift toolchain on Linux).

```sh
git clone https://github.com/claudeskillsman/AppStoreReady.git
cd AppStoreReady
swift build -c release
cp .build/release/appstoreready /usr/local/bin/
```

To run without installing:

```sh
swift run appstoreready scan /path/to/MyApp
```

## Usage

```
appstoreready scan [<path>] [options]
appstoreready rules [--format text|json]
```

`<path>` can be an `.xcodeproj`, an `.xcworkspace`, or a directory. For a directory, AppStoreReady finds the projects inside it (skipping `Pods`, `Carthage`, `DerivedData`, `.build`, `node_modules`, and similar folders) and any top-level workspace. `scan` is the default subcommand, so `appstoreready ./MyApp` works too.

| Option | Description |
| --- | --- |
| `-f, --format text\|json` | Terminal report (default) or machine-readable JSON. |
| `-o, --output <file>` | Write the report to a file. |
| `-c, --configuration <name>` | Inspect this build configuration. By default each target uses the Archive configuration of the scheme that builds it, then `Release`, then the project default. |
| `--fail-on error\|warning\|never` | Lowest severity that makes the process exit with status 1. Default `error`. |
| `--disable <ID> ...` | Skip rules, for example `--disable ASR008 ASR010`. |
| `--config <file>` | Read suppressions from this file instead of `.appstoreready.yml` in the scan root. |
| `--no-suppressions` | Ignore `.appstoreready.yml` and report everything. |
| `--no-color` | Disable ANSI colors. Colors are also off when output is not a terminal or `NO_COLOR` is set. |
| `-v, --verbose` | Show messages and evidence for passing checks too. |

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | The scan finished and nothing reached the `--fail-on` threshold. |
| 1 | The scan finished and at least one finding reached the threshold. |
| 2 | The scan could not run: the path does not exist, contains no project, `--configuration` names a configuration that does not exist, or `.appstoreready.yml` is invalid. |
| 64 | Invalid command-line arguments. |

### Severities

| Severity | Label | Meaning |
| --- | --- | --- |
| `ERROR` | FAIL | Very likely to break the upload, the build, or the app. |
| `WARNING` | WARN | Probably wrong; review before submitting. |
| `MANUAL_REVIEW` | REVIEW | A static scan cannot decide; a person needs to check. |
| `INFO` | INFO | A best-practice recommendation or context about the scan. |
| `PASS` | PASS | The check ran and found nothing to report. |

Every finding also carries a confidence level (`high`: read directly from configuration, `medium`: inferred from source patterns, `low`: heuristic) and one of four classifications:

| Classification | Meaning |
| --- | --- |
| Verified configuration issue | A high-confidence `ERROR` or `WARNING` read directly from the project, such as a malformed entitlement or a background task identifier that is not permitted. |
| Potential issue | An `ERROR` or `WARNING` that depends on inference, such as an API detected by text matching or a setting your build system might override. |
| Best-practice recommendation | `INFO`. Not a requirement; following it avoids friction, for example declaring export compliance so App Store Connect stops asking on every upload. |
| Requires manual review | `MANUAL_REVIEW`. The topic applies, but only a person can judge it, for example App Review Guideline 4.8 when a third-party sign-in SDK is present. |

Each non-passing finding includes the rule ID, severity, message, file and line where known, why it matters, a suggested fix, and a link to the Apple documentation it is based on.

## Examples

Scan a workspace and inspect the Release configuration explicitly:

```sh
appstoreready scan MyApp.xcworkspace --configuration Release
```

Fail a CI job on warnings as well as errors and keep a JSON report as an artifact:

```sh
appstoreready scan . --fail-on warning --format json --output appstoreready.json
```

A GitHub Actions step on a macOS runner:

```yaml
- name: App Store readiness
  run: |
    swift build -c release --package-path tools/AppStoreReady
    tools/AppStoreReady/.build/release/appstoreready scan . --no-color
```

Silence a known, intentional match of the secret scanner by adding a marker comment on that line, or with a suppression (see below):

```swift
static let publicDemoKey = "pk_demo_1234567890abcdef" // appstoreready:ignore
```

The JSON report has this shape (abridged):

```json
{
  "findings" : [
    {
      "category" : "app-configuration",
      "classification" : "verified-issue",
      "confidence" : "high",
      "configuration" : "Release",
      "documentationURL" : "https://developer.apple.com/documentation/xcode/specifying-your-apps-launch-screen",
      "evidence" : [ ],
      "file" : "Hardening/Info.plist",
      "message" : "'Hardening' declares neither UILaunchStoryboardName nor UILaunchScreen.",
      "ruleID" : "ASR011",
      "severity" : "ERROR",
      "suggestedFix" : "Add a launch screen: set Launch Screen File in the target's General settings, ...",
      "target" : "Hardening",
      "title" : "Missing launch screen",
      "whyItMatters" : "Apple's documentation states that every iOS app must provide a launch screen, which the system shows while the app launches."
    }
  ],
  "projects" : [ "Hardening.xcodeproj" ],
  "scannedPath" : "Tests/Fixtures/Hardening",
  "summary" : { "errors" : 7, "info" : 2, "manualReview" : 8, "passes" : 8, "suppressed" : 0, "warnings" : 10 },
  "suppressed" : [ ],
  "targets" : [ "Hardening (Release)" ],
  "tool" : "AppStoreReady",
  "version" : "0.2.0"
}
```

## Suppressing findings

Put suppressions in `.appstoreready.yml` at the root of the scanned folder (or pass `--config <file>`). Each entry needs a rule ID and a reason; `expires`, `path`, and `target` are optional.

```yaml
version: 1
suppressions:
  - rule: ASR008
    reason: AWS documentation example key used in a unit test helper, not a real credential
    path: MyApp/Debug/SampleKeys.swift
    expires: 2026-12-31
  - rule: ASR018
    reason: Distributed outside the Mac App Store
    target: MyMacApp
  - rule: ASR015
    reason: Local test server only reachable on the office network
    path: "**/Staging/*.swift"
```

| Key | Required | Meaning |
| --- | --- | --- |
| `rule` | yes | The rule ID, for example `ASR014`. Unknown IDs are an error. |
| `reason` | yes | Why the finding does not apply. It is shown in the report. |
| `expires` | no | `YYYY-MM-DD`. The suppression stops applying after this date (UTC). |
| `path` | no | Only findings in this file. `*` and `?` match within a folder, `**` across folders, and a trailing `/` matches everything below a folder. |
| `target` | no | Only findings for this target. |

Suppressed findings are left out of the main list and the exit code, and listed with their reason in a separate "Suppressed by .appstoreready.yml" section (and the `suppressed` array in JSON). Suppressions never hide `PASS` results. The engine adds an `ASR000` finding to keep suppressions honest:

- `WARNING` **Critical security finding suppressed** whenever a suppression hides an `ERROR` in the Security category, such as a hardcoded secret. It names the hidden location and the reason, so it still counts toward `--fail-on warning`.
- `WARNING` **Suppression expired** for entries past their `expires` date, which are no longer applied.
- `INFO` **Suppression matched nothing** for entries that no longer hide anything.

An invalid file (unknown keys, a missing reason, tabs, a bad date) stops the scan with exit code 2 and the line number of the problem. `--no-suppressions` ignores the file.

## Checks

Run `appstoreready rules` for the same list, with each rule's rationale and sources, from the tool itself. Application, app extension, watchOS app, and App Clip targets are checked; frameworks, libraries, and test bundles are skipped. Apple sources were retrieved on 2026-10-08; requirements change, so the linked pages are the authority.

### App Configuration

| ID | Check | Reports | Source |
| --- | --- | --- | --- |
| ASR001 | Project files are readable | `ERROR` for a `project.pbxproj`, Info.plist, entitlements file, or privacy manifest that cannot be parsed, or an Info.plist / `.xcconfig` / entitlements file that build settings point to but that does not exist. `WARNING` for malformed schemes, icon `Contents.json`, or lock files. Checks that depend on an unreadable file are skipped rather than guessed. | [Information property list](https://developer.apple.com/documentation/bundleresources/managing-your-app-s-information-property-list) |
| ASR002 | Bundle identifier | `ERROR` when `CFBundleIdentifier` is missing, resolves to an empty value, or contains characters other than `A-Z a-z 0-9 - .`. `WARNING` for template placeholders such as `com.example.*`, and for an extension whose identifier is not prefixed by its app's. | [CFBundleIdentifier](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier) |
| ASR003 | Version number | `ERROR` when `CFBundleShortVersionString` / `MARKETING_VERSION` is missing, empty, or not period-separated integers. `WARNING` when an extension's version differs from its app's. | [CFBundleShortVersionString](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring) |
| ASR004 | Build number | `ERROR` when `CFBundleVersion` / `CURRENT_PROJECT_VERSION` is missing, empty, or not period-separated integers; Apple documents the key as required by the App Store. `WARNING` when an extension's build number differs from its app's. | [CFBundleVersion](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion) |
| ASR011 | Launch screen | `ERROR` (verified) when an iOS app declares neither `UILaunchStoryboardName` nor `UILaunchScreen` (including Xcode's generated launch screen); Apple states that every iOS app must provide one. `WARNING` when the named storyboard is not in the project. | [Specifying your app's launch screen](https://developer.apple.com/documentation/xcode/specifying-your-apps-launch-screen) |
| ASR019 | Background modes | `ERROR` (verified) when code registers a `BGTaskScheduler` identifier that is missing from `BGTaskSchedulerPermittedIdentifiers`, since registration then fails. `WARNING` for `UIBackgroundModes` values not in Apple's list, permitted identifiers with no registered handler, and task identifiers without the `fetch` or `processing` mode. `MANUAL_REVIEW` for declared modes under Guideline 2.5.4. | [UIBackgroundModes](https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes), [BGTaskSchedulerPermittedIdentifiers](https://developer.apple.com/documentation/bundleresources/information-property-list/bgtaskschedulerpermittedidentifiers), [Guideline 2.5.4](https://developer.apple.com/app-store/review/guidelines/#software-requirements) |

### Privacy

| ID | Check | Reports | Source |
| --- | --- | --- | --- |
| ASR007 | Privacy manifest | Detects the five [required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) categories in a target's source. Only when such usage is found does a missing manifest, a manifest outside the target, or an undeclared category become an `ERROR`; App Store Connect has rejected undeclared usage since May 1, 2024. macOS targets are exempt, as in Apple's documentation. Validates the manifest itself: API categories and reason codes not in Apple's lists (`ERROR`), SDK-only reasons such as `C56D.1` in an app (`WARNING`), collected data entries missing any of the four required keys (`ERROR`) or using undocumented data types or purposes (`WARNING`), and `NSPrivacyTracking` / `NSPrivacyTrackingDomains` that contradict each other (`WARNING`). `MANUAL_REVIEW` when there is no manifest and no detected usage, or when App Tracking Transparency APIs are used while the manifest declares no tracking. | [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [NSPrivacyAccessedAPIType](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype), [Describing data use](https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests) |
| ASR020 | Third-party SDK privacy manifests | Matches dependencies from `Package.resolved`, `Podfile.lock`, `Cartfile.resolved`, and vendored `.framework` / `.xcframework` folders against Apple's list of 86 SDKs that require a privacy manifest and signature. `WARNING` when a listed SDK's files are present without a `PrivacyInfo.xcprivacy` (CocoaPods `Pods/` folders and vendored frameworks). `MANUAL_REVIEW` when the SDK's files are not in the scanned folder (Swift packages, Carthage). Signatures are not checked. | [Third-party SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/) |

### Security

| ID | Check | Reports | Source |
| --- | --- | --- | --- |
| ASR008 | Hardcoded secrets | `ERROR` for AWS access keys, GitHub, Stripe live, Slack, OpenAI/Anthropic and FCM server tokens, and private key blocks. `WARNING` for Google API keys and high-entropy values assigned to names like `apiKey`, `secret`, `token`, or `password` in Swift, Objective-C, plists, `.xcconfig`, `.env`, and schemes. Matches in test or fixture folders are downgraded. Secret values are never printed. | [Storing keys in the keychain](https://developer.apple.com/documentation/security/storing-keys-in-the-keychain) |
| ASR014 | App Transport Security | `WARNING` for `NSAllowsArbitraryLoads`, `NSAllowsArbitraryLoadsForMedia`, `NSAllowsArbitraryLoadsInWebContent`, per-domain `NSExceptionAllowsInsecureHTTPLoads` (except localhost), and a minimum TLS version below 1.2. Apple's documentation says each of these needs a justification during App Store review. | [Preventing insecure network connections](https://developer.apple.com/documentation/security/preventing-insecure-network-connections), [NSAppTransportSecurity](https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity) |
| ASR015 | Insecure HTTP URLs | `WARNING` for `"http://…"` string literals in a target's code whose host has no ATS exception. Skipped when ATS is disabled globally (ASR014 reports that). | [Preventing insecure network connections](https://developer.apple.com/documentation/security/preventing-insecure-network-connections) |
| ASR016 | Credential files | `ERROR` when a `.p12`, `.pfx`, or `.p8` file is a member of a target and would ship inside the app. `WARNING` when one is elsewhere in the project folder, `INFO` in test folders. File contents are never read into the report. | [Storing keys in the keychain](https://developer.apple.com/documentation/security/storing-keys-in-the-keychain), [App Store Connect API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) |

### Permissions

| ID | Check | Reports | Source |
| --- | --- | --- | --- |
| ASR006 | Privacy usage descriptions | Searches the target's source for APIs that request protected resources (camera, microphone, speech, photos, location, contacts, calendars, reminders, Bluetooth, Health, motion, tracking, Face ID, media library, NFC, HomeKit, local network). `ERROR` when an access request is found and the purpose string is missing, and when `NSLocationAlwaysAndWhenInUseUsageDescription` is set without `NSLocationWhenInUseUsageDescription`, which Apple requires for both kinds of authorization. `WARNING` when only a related type is referenced, and for purpose strings that are empty or say "TODO". | [Requesting access to protected resources](https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources), [Location authorization](https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services) |

### Signing

| ID | Check | Reports | Source |
| --- | --- | --- | --- |
| ASR017 | Signing configuration | `ERROR` when `CODE_SIGNING_ALLOWED` or `CODE_SIGNING_REQUIRED` is `NO` for the archive configuration. `WARNING` for manual signing without a provisioning profile, automatic signing without `DEVELOPMENT_TEAM`, and extensions signed by a different team than their app. | [Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference#Signing), [Distributing your app](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases) |
| ASR018 | Entitlements | `ERROR` (verified) for associated domains that are not `<service>:<domain>` with `applinks`, `webcredentials`, `activitycontinuation`, or `appclips`; app groups not named `group.<name>` (or `<team ID>.<name>` on macOS); `aps-environment` other than `development` or `production`; and macOS apps without the App Sandbox, which Apple states is required for the Mac App Store. HealthKit without both usage descriptions is an `ERROR` when the code requests authorization (Apple says the app crashes), otherwise a `WARNING`. `WARNING` for `get-task-allow` in the archived entitlements. | [Associated Domains](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.associated-domains), [App Groups](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups), [aps-environment](https://developer.apple.com/documentation/bundleresources/entitlements/aps-environment), [macOS App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox) |

### Assets

| ID | Check | Reports | Source |
| --- | --- | --- | --- |
| ASR005 | App icon | `ERROR` when an app names no icon set, the named `.appiconset` does not exist, or it contains no images. `WARNING` for references to missing image files or no 1024x1024 icon. | [Configuring your app icon](https://developer.apple.com/documentation/xcode/configuring-your-app-icon) |
| ASR021 | App icon images | Reads each PNG header (no decoding). `WARNING` (verified) when an image's pixel size is not the slot's size × scale. `INFO` when the default-appearance 1024-pixel icon has an alpha channel; the Human Interface Guidelines ask for an opaque background layer, and dark variants are meant to be transparent. `INFO` for non-PNG icons, which are not inspected. | [Configuring your app icon](https://developer.apple.com/documentation/xcode/configuring-your-app-icon), [HIG: App icons](https://developer.apple.com/design/human-interface-guidelines/app-icons) |

### Build Configuration

| ID | Check | Reports | Source |
| --- | --- | --- | --- |
| ASR009 | Debug configuration | `WARNING` when a scheme's Archive action uses a configuration named Debug, or the archive configuration has `SWIFT_OPTIMIZATION_LEVEL = -Onone`, `GCC_OPTIMIZATION_LEVEL = 0`, or a `DEBUG` compilation condition. `INFO` when no scheme archives the target, so Release was assumed. | [Customizing the build schemes](https://developer.apple.com/documentation/xcode/customizing-the-build-schemes-for-a-project) |
| ASR012 | Deployment target | `ERROR` (verified) for an iOS deployment target below 13, which App Store Connect has refused since September 9, 2026. `WARNING` below the lowest target Xcode 26 supports for upload (iOS/iPadOS/tvOS 15, watchOS 8, macOS 11, visionOS 1); Xcode 26 has been required for uploads since April 28, 2026. Multiplatform targets (`SDKROOT = auto`) are checked for each platform in `SUPPORTED_PLATFORMS`. The SDK used to build is not visible to a static scan. | [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/), [Xcode support](https://developer.apple.com/support/xcode/) |
| ASR022 | Release build settings | `INFO` when the archive configuration does not produce dSYMs (`DEBUG_INFORMATION_FORMAT`) or has `ENABLE_TESTABILITY = YES`. | [Build settings reference](https://developer.apple.com/documentation/xcode/build-settings-reference) |

### Accessibility

| ID | Check | Reports | Source |
| --- | --- | --- | --- |
| ASR010 | Accessibility | `INFO` reminder that accessibility needs runtime testing (VoiceOver, Dynamic Type, Accessibility Inspector). | [Accessibility](https://developer.apple.com/accessibility/) |
| ASR023 | Accessibility hints | `INFO`, low confidence, when an app's UI code uses no accessibility label APIs or uses fixed font sizes without Dynamic Type support. A `PASS` here only means such APIs appear in the code; it never means the app is accessible. | [Accessibility for UIKit](https://developer.apple.com/documentation/uikit/accessibility-for-uikit) |

### App Store Metadata

| ID | Check | Reports | Source |
| --- | --- | --- | --- |
| ASR013 | Encryption export compliance | `INFO` when `ITSAppUsesNonExemptEncryption` is absent, because App Store Connect then asks the export compliance questions on every upload. `MANUAL_REVIEW` when it is `YES` (documentation and `ITSEncryptionExportComplianceCode` are needed). | [ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption) |
| ASR024 | App Store metadata | For macOS apps, `WARNING` when `LSApplicationCategoryType` is not one of Apple's 40 category values and `INFO` when it is missing. One `MANUAL_REVIEW` item per scan for what only App Store Connect holds: the privacy policy link (Guideline 5.1.1(i)), App Privacy details, final metadata and a demo account (Guideline 2.1). | [LSApplicationCategoryType](https://developer.apple.com/documentation/bundleresources/information-property-list/lsapplicationcategorytype), [Guideline 5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage) |

### Manual Review

| ID | Check | Reports | Source |
| --- | --- | --- | --- |
| ASR025 | App Review Guideline topics | `MANUAL_REVIEW` when the code shows that a guideline applies: StoreKit purchase APIs or a purchases SDK (3.1.1 In-App Purchase; review prompts don't count), a third-party sign-in SDK (4.8 Login Services), account sign-up code (5.1.1(v) account deletion). Also lists Run Script build phases, which AppStoreReady never runs or analyzes. | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) |
| ASR000 | Suppressions | Notices about `.appstoreready.yml`; see [Suppressing findings](#suppressing-findings). | This README |

## Using with Claude (optional)

The [`integrations/claude`](integrations/claude) folder has an optional skill for Claude Code that runs the audit, checks each finding against your code, and turns the report into a prioritized list of fixes. AppStoreReady itself doesn't depend on it.

## Architecture

```
Sources/
  AppStoreReadyCLI/          Argument parsing, output, exit codes (swift-argument-parser)
  AppStoreReadyCore/         Foundation-only library; usable without the CLI
    Models/                  Finding, Severity, Confidence, RuleMetadata, ScanContext, project model
    Scanners/                Discovery, pbxproj / xcconfig / scheme / workspace parsing,
                             build-setting resolution, file collection, lock files
    Rules/                   Rule protocol, RuleRegistry, the built-in rules
    Reporters/               Text and JSON reporters
    Engine/                  AuditEngine, suppressions (.appstoreready.yml), exit status policy
    Utilities/               BuildSettings, API usage catalog, PNG header reader,
                             redaction, regex helpers
Tests/
  AppStoreReadyCoreTests/    XCTest suites
  Fixtures/                  Small Xcode projects used by the tests
```

A scan runs in three steps:

1. **Scan** (`ProjectScanner`). Finds projects, parses each `project.pbxproj` with a small built-in parser for Xcode's ASCII property list format, reads schemes and workspaces, and resolves every app and extension target for the configuration that would be archived. Build settings are layered the way Xcode does it: defaults, project `.xcconfig`, project settings, target `.xcconfig`, target settings, with `$(inherited)` and `$(VAR)` / `${VAR:modifier}` expansion. The effective Info.plist merges `GENERATE_INFOPLIST_FILE` / `INFOPLIST_KEY_*` settings with the `INFOPLIST_FILE` file. Target membership comes from Sources and Resources build phases and from Xcode 16 synchronized folders, including their membership exceptions. Entitlements files named by `CODE_SIGN_ENTITLEMENTS` are read for each target. Text files, privacy manifests, app icon sets (with PNG headers), and dependency lock files under the scan root are collected once.
2. **Evaluate** (`AuditEngine`). Each `Rule` receives the read-only `ScanContext` and returns `Finding`s. The engine then applies suppressions from `.appstoreready.yml` and adds `ASR000` notices.
3. **Report** (`Reporter`). `TextReporter` or `JSONReporter` renders the `ScanReport`; the CLI maps the summary to an exit code.

## Contributing

Contributions are welcome, especially new rules backed by Apple documentation, fixtures that reproduce real-world project layouts, and fixes for false positives. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide, and use the issue templates to report wrong findings or suggest rules.

```sh
swift build
swift test
swift run appstoreready scan Tests/Fixtures/MissingConfig
```

To add a rule:

1. Create a type in `Sources/AppStoreReadyCore/Rules/` that conforms to `Rule`. Give it the next free `ASRnnn` identifier (identifiers are never reused), a title, a description, a rationale ("why it matters"), one of the ten categories, and at least one `Reference` to the Apple documentation that supports it.
2. Implement `evaluate(_:)`. Build findings with the `finding(...)` helper so the rule ID, category, rationale, and documentation link are filled in. Return a `PASS` finding when the check ran cleanly so users can see it was evaluated.
3. Pick severity, confidence, and classification honestly. Use a verified `ERROR` only when the problem is demonstrable from the project; only describe something as an Apple requirement when Apple's documentation says so, and link it. Use `INFO` for best practices and `MANUAL_REVIEW` when the answer depends on things a static scan cannot see.
4. Never put secret values, or parts of them, in a finding. Use `Redactor.describe(_:)`.
5. Register the rule in `RuleRegistry.builtIn`, add a fixture under `Tests/Fixtures/` if needed, and add tests for both the passing and the failing case.

Rules must not access the network, spawn processes, or execute anything from the scanned project. `SecurityModelTests` enforces part of this.

Fixture projects are deliberately small, hand-checkable Xcode projects generated by `Scripts/generate-fixtures.py` (`rm -rf Tests/Fixtures && python3 Scripts/generate-fixtures.py Tests/Fixtures`). If you add one, open it in Xcode at least once to make sure it is a valid project.

## Limitations

- **Static analysis only.** AppStoreReady never builds the project, so it cannot see generated code, build-phase script output, or what binary SDKs do. Code from Swift packages and CocoaPods is not attributed to your targets. API detection is text matching on source files; it can miss usage (for example through wrappers or dynamic dispatch) and can be fooled by identically named symbols.
- **Build settings are approximated.** Settings layering and variable expansion cover the common cases, but SDK- and architecture-conditional settings (`KEY[sdk=...]`), settings that only exist inside Xcode (most `BUILT_PRODUCTS_DIR`-style values), and command-line overrides are not modelled.
- **Extension relationships are inferred.** Version and bundle ID comparisons between an extension and its app assume the project has exactly one application target.
- **Not every platform detail is checked.** tvOS layered icons (`.brandassets`) and macOS `.icns` icons are not validated. Entitlement values are checked, but provisioning profiles, certificates, and code signatures (including SDK signatures) are not.
- **Dependencies are read from lock files.** Swift packages and Carthage checkouts usually live outside the project, so their privacy manifests can only be flagged for manual review. SDKs added without a lock file are only found when they are committed as `.framework` or `.xcframework` folders.
- **Requirements change.** Apple's lists (required reason codes, third-party SDKs, deployment targets, background modes, categories) were copied from Apple's documentation on 2026-10-08 and need updating when Apple changes them.
- **Secret scanning is heuristic.** It catches common credential formats and suspicious assignments but not every secret, and it can flag non-secrets. Dependency folders (`Pods`, `Carthage`, `SourcePackages`, `vendor`, `node_modules`, build output) are not scanned.
- **No review prediction.** A clean report does not mean an app will be approved, and a finding does not mean it will be rejected.

## Security model

AppStoreReady is designed to be safe to run on code you do not fully trust.

- **Read-only.** It only reads files. It never writes inside the scanned project (the optional `--output` report goes where you point it). Lock files, entitlements, and `.appstoreready.yml` are parsed as data; package managers are never run, and image files are only read for their PNG header.
- **No code execution.** It never runs build phases, "Run Script" phases, package plugins, schemes, `xcodebuild`, or any other process. Project files are parsed as data.
- **No network access.** It makes no network requests, uploads nothing, and sends no telemetry. Project contents never leave your machine.
- **Secrets are never printed.** Findings for suspected credentials contain the file, line, credential type, and length only, in both text and JSON output.
- **Bounded file access.** Symbolic links are not followed, binary files are skipped, and file size (2 MB) and file count (50,000) are capped.

If you find a way to make AppStoreReady execute code, reach the network, or leak a secret value, please report it privately as described in [SECURITY.md](SECURITY.md) rather than in a public issue.

## License

AppStoreReady is released under the [MIT License](LICENSE).
