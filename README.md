# AppStoreReady

AppStoreReady is an open-source command-line tool that audits an Xcode project for likely App Store submission problems before you upload a build: missing bundle identifiers and version numbers, absent app icons, missing privacy purpose strings, required-reason APIs without a privacy manifest, hardcoded secrets, and archives built with debug settings.

Example output (abridged):

```
$ appstoreready scan ./MyApp

AppStoreReady — iOS App Audit

Scanned ./MyApp
  Project: MyApp.xcodeproj
  Target:  MyApp (Release)

PASS    Project files parsed
PASS    Bundle identifier configured  [MyApp]
PASS    Version number configured  [MyApp]
PASS    Build number configured  [MyApp]
PASS    App icon configuration detected  [MyApp]
WARN    Privacy usage descriptions need review  [MyApp]
        'MyApp' references Photo library APIs but its Info.plist has no NSPhotoLibraryUsageDescription. ...
        File: MyApp/Gallery.swift:14
        Fix: Add NSPhotoLibraryUsageDescription to the Info.plist ...
PASS    Privacy manifest present  [MyApp]
FAIL    Potential hardcoded secret detected
        MyApp/Config.swift:5 contains a value matching the pattern for: AWS access key ID. ...
        File: MyApp/Config.swift:5
        • AWS access key ID, value [REDACTED: 20 characters]
        Fix: Remove the value from the project, rotate the credential, ...
PASS    Archive configuration uses release settings  [MyApp]
INFO    Accessibility audit requires runtime testing

Summary: 1 failure, 1 warning, 1 manual review item.
7 checks passed.
AppStoreReady reports likely problems found by static analysis. It cannot predict App Review decisions.
```

AppStoreReady is a static analyser. It points out things that are likely to break an upload, crash the app, or draw attention in review, and it says how confident it is about each finding. It does not and cannot predict App Review decisions.

## Installation

AppStoreReady is a Swift package. It needs Swift 5.9 or later (Xcode 15+ on macOS, or a Swift toolchain on Linux).

```sh
git clone https://github.com/<owner>/AppStoreReady.git
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
| `--no-color` | Disable ANSI colors. Colors are also off when output is not a terminal or `NO_COLOR` is set. |
| `-v, --verbose` | Show messages and evidence for passing checks too. |

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | The scan finished and nothing reached the `--fail-on` threshold. |
| 1 | The scan finished and at least one finding reached the threshold. |
| 2 | The scan could not run: the path does not exist, contains no project, or `--configuration` names a configuration that does not exist. |
| 64 | Invalid command-line arguments. |

### Severities

| Severity | Label | Meaning |
| --- | --- | --- |
| `ERROR` | FAIL | Very likely to break the upload, the build, or the app. |
| `WARNING` | WARN | Probably wrong; review before submitting. |
| `MANUAL_REVIEW` | REVIEW | A static scan cannot decide; a person needs to check. |
| `INFO` | INFO | Context about the scan or a reminder. |
| `PASS` | PASS | The check ran and found nothing to report. |

The summary line counts `MANUAL_REVIEW` and `INFO` findings together as manual review items. Every finding also carries a confidence level (`high`: read directly from configuration, `medium`: inferred from source patterns, `low`: heuristic).

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

Silence a known, intentional match of the secret scanner by adding a marker comment on that line:

```swift
static let publicDemoKey = "pk_demo_1234567890abcdef" // appstoreready:ignore
```

The JSON report has this shape (abridged):

```json
{
  "findings" : [
    {
      "category" : "configuration",
      "confidence" : "high",
      "configuration" : "Release",
      "documentationURL" : "https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier",
      "evidence" : [ "CFBundleIdentifier = com.acme.validapp" ],
      "file" : "ValidApp.xcodeproj/project.pbxproj",
      "message" : "'ValidApp' uses bundle identifier 'com.acme.validapp'.",
      "ruleID" : "ASR002",
      "severity" : "PASS",
      "target" : "ValidApp",
      "title" : "Bundle identifier configured"
    }
  ],
  "projects" : [ "ValidApp.xcodeproj" ],
  "scannedPath" : "Tests/Fixtures/ValidApp",
  "summary" : { "errors" : 0, "info" : 1, "manualReview" : 0, "passes" : 9, "warnings" : 0 },
  "targets" : [ "ValidApp (Release)" ],
  "tool" : "AppStoreReady",
  "version" : "0.1.0"
}
```

## Checks

Run `appstoreready rules` for the same list from the tool itself. Application, app extension, watchOS app, and App Clip targets are checked; frameworks, libraries, and test bundles are skipped.

| ID | Check | Reports |
| --- | --- | --- |
| ASR001 | Project files are readable | `ERROR` for a `project.pbxproj`, Info.plist, or privacy manifest that cannot be parsed, or an Info.plist / `.xcconfig` that build settings point to but that does not exist. `WARNING` for malformed schemes or icon `Contents.json`. Checks that depend on an unreadable file are skipped rather than guessed. |
| ASR002 | Bundle identifier | `ERROR` when `CFBundleIdentifier` is missing, resolves to an empty value (for example `$(PRODUCT_BUNDLE_IDENTIFIER)` with the setting unset), or contains characters other than `A-Z a-z 0-9 - .` ([Apple docs](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleidentifier)). `WARNING` for template placeholders such as `com.example.*`, and for an extension whose identifier is not prefixed by its app's. |
| ASR003 | Version number | `ERROR` when `CFBundleShortVersionString` / `MARKETING_VERSION` is missing, empty, or not one to three period-separated integers ([Apple docs](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring)). `WARNING` when an extension's version differs from its app's. |
| ASR004 | Build number | `ERROR` when `CFBundleVersion` / `CURRENT_PROJECT_VERSION` is missing, empty, or not period-separated integers. Apple documents this key as required by the App Store ([Apple docs](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleversion)). `WARNING` when an extension's build number differs from its app's. |
| ASR005 | App icon | `ERROR` when an app sets no `ASSETCATALOG_COMPILER_APPICON_NAME` and declares no icon in Info.plist, when the named `.appiconset` does not exist, or when it contains no images. `WARNING` for references to missing image files or no 1024x1024 icon. |
| ASR006 | Privacy usage descriptions | Searches the target's source for APIs that request protected resources (camera, microphone, speech, photos, location, contacts, calendars, reminders, Bluetooth, Health, motion, tracking, Face ID, media library, NFC, HomeKit, local network). `ERROR` when an access request call is found and the purpose string is missing; Apple states that [App Review rejects](https://developer.apple.com/documentation/uikit/requesting-access-to-protected-resources) apps with such code and no purpose string. `WARNING` when only a related type is referenced, and for purpose strings that are empty or say "TODO". |
| ASR007 | Privacy manifest | Detects Apple's [required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) categories (file timestamps, system boot time, disk space, active keyboards, user defaults). Only when such usage is found in the target does a missing manifest, a manifest that is not in the target, or an undeclared category become an `ERROR`. Without detected usage, a missing manifest is `MANUAL_REVIEW`, because the need can come from SDKs or data collection a static scan cannot see. Also warns when `NSPrivacyTracking` is true with no tracking domains. |
| ASR008 | Hardcoded secrets | `ERROR` for AWS access keys, GitHub, Stripe live, Slack, OpenAI/Anthropic and FCM server tokens, and private key blocks. `WARNING` for Google API keys and high-entropy values assigned to names like `apiKey`, `secret`, `token`, or `password` in Swift, Objective-C, plists, `.xcconfig`, `.env`, and schemes. Matches in test or fixture folders are downgraded to `WARNING` with low confidence. Secret values are never printed. |
| ASR009 | Debug configuration | `WARNING` when a scheme's Archive action uses a configuration named Debug, or the archive configuration has `SWIFT_OPTIMIZATION_LEVEL = -Onone`, `GCC_OPTIMIZATION_LEVEL = 0`, or a `DEBUG` compilation condition / preprocessor definition. `INFO` when no scheme archives the target, so Release was assumed. |
| ASR010 | Accessibility | `INFO` reminder that accessibility needs runtime testing (VoiceOver, Dynamic Type, Accessibility Inspector). |

## Architecture

```
Sources/
  AppStoreReadyCLI/          Argument parsing, output, exit codes (swift-argument-parser)
  AppStoreReadyCore/         Foundation-only library; usable without the CLI
    Models/                  Finding, Severity, Confidence, RuleMetadata, ScanContext, project model
    Scanners/                Discovery, pbxproj / xcconfig / scheme / workspace parsing,
                             build-setting resolution, file collection
    Rules/                   Rule protocol, RuleRegistry, the built-in rules
    Reporters/               Text and JSON reporters
    Engine/                  AuditEngine, exit status policy
    Utilities/               BuildSettings, API usage catalog, redaction, regex helpers
Tests/
  AppStoreReadyCoreTests/    XCTest suites
  Fixtures/                  Small Xcode projects used by the tests
```

A scan runs in three steps:

1. **Scan** (`ProjectScanner`). Finds projects, parses each `project.pbxproj` with a small built-in parser for Xcode's ASCII property list format, reads schemes and workspaces, and resolves every app and extension target for the configuration that would be archived. Build settings are layered the way Xcode does it: defaults, project `.xcconfig`, project settings, target `.xcconfig`, target settings, with `$(inherited)` and `$(VAR)` / `${VAR:modifier}` expansion. The effective Info.plist merges `GENERATE_INFOPLIST_FILE` / `INFOPLIST_KEY_*` settings with the `INFOPLIST_FILE` file. Target membership comes from Sources and Resources build phases and from Xcode 16 synchronized folders, including their membership exceptions. Text files, privacy manifests, and app icon sets under the scan root are collected once.
2. **Evaluate** (`AuditEngine`). Each `Rule` receives the read-only `ScanContext` and returns `Finding`s.
3. **Report** (`Reporter`). `TextReporter` or `JSONReporter` renders the `ScanReport`; the CLI maps the summary to an exit code.

## Contributing

Contributions are welcome, especially new rules backed by Apple documentation, fixtures that reproduce real-world project layouts, and fixes for false positives.

```sh
swift build
swift test
swift run appstoreready scan Tests/Fixtures/MissingConfig
```

To add a rule:

1. Create a type in `Sources/AppStoreReadyCore/Rules/` that conforms to `Rule`. Give it the next free `ASRnnn` identifier (identifiers are never reused), a title, a description, a category, and a documentation URL.
2. Implement `evaluate(_:)`. Build findings with the `finding(...)` helper so the rule ID, category, and documentation link are filled in. Return a `PASS` finding when the check ran cleanly so users can see it was evaluated.
3. Pick severity and confidence honestly. Use `ERROR` only when the problem is demonstrable from the project; only describe something as an Apple requirement when Apple's documentation says so, and link it. Use `MANUAL_REVIEW` when the answer depends on things a static scan cannot see.
4. Never put secret values, or parts of them, in a finding. Use `Redactor.describe(_:)`.
5. Register the rule in `RuleRegistry.builtIn`, add a fixture under `Tests/Fixtures/` if needed, and add tests for both the passing and the failing case.

Rules must not access the network, spawn processes, or execute anything from the scanned project. `SecurityModelTests` enforces part of this.

Fixture projects are deliberately small, hand-checkable Xcode projects. If you add one, open it in Xcode at least once to make sure it is a valid project.

## Limitations

- **Static analysis only.** AppStoreReady never builds the project, so it cannot see generated code, build-phase script output, or what binary SDKs do. Code from Swift packages and CocoaPods is not attributed to your targets. API detection is text matching on source files; it can miss usage (for example through wrappers or dynamic dispatch) and can be fooled by identically named symbols.
- **Build settings are approximated.** Settings layering and variable expansion cover the common cases, but SDK- and architecture-conditional settings (`KEY[sdk=...]`), settings that only exist inside Xcode (most `BUILT_PRODUCTS_DIR`-style values), and command-line overrides are not modelled.
- **Extension relationships are inferred.** Version and bundle ID comparisons between an extension and its app assume the project has exactly one application target.
- **Not every platform detail is checked.** tvOS layered icons (`.brandassets`), macOS `.icns` icons, and per-platform icon size requirements are not validated. Entitlements, code signing, and provisioning profiles are not inspected.
- **Secret scanning is heuristic.** It catches common credential formats and suspicious assignments but not every secret, and it can flag non-secrets. Dependency folders (`Pods`, `Carthage`, `SourcePackages`, `vendor`, `node_modules`, build output) are not scanned.
- **No review prediction.** A clean report does not mean an app will be approved, and a finding does not mean it will be rejected.

## Security model

AppStoreReady is designed to be safe to run on code you do not fully trust.

- **Read-only.** It only reads files. It never writes inside the scanned project (the optional `--output` report goes where you point it).
- **No code execution.** It never runs build phases, "Run Script" phases, package plugins, schemes, `xcodebuild`, or any other process. Project files are parsed as data.
- **No network access.** It makes no network requests, uploads nothing, and sends no telemetry. Project contents never leave your machine.
- **Secrets are never printed.** Findings for suspected credentials contain the file, line, credential type, and length only, in both text and JSON output.
- **Bounded file access.** Symbolic links are not followed, binary files are skipped, and file size (2 MB) and file count (50,000) are capped.

If you find a way to make AppStoreReady execute code, reach the network, or leak a secret value, please report it privately to the maintainers rather than in a public issue.

## License

AppStoreReady is released under the [MIT License](LICENSE).
