# Changelog

## 0.2.0

- 15 new rules (ASR011–ASR025): launch screen, deployment target, encryption export compliance, App Transport Security, insecure HTTP URLs, credential files, signing, entitlements, background modes, third-party SDK privacy manifests, app icon images, release build settings, accessibility hints, App Store metadata, and App Review Guideline topics.
- ASR006 checks that Always location access also has the When In Use description.
- ASR007 validates privacy manifest reason codes, collected data entries, and tracking settings against Apple's documented values; required-reason checks no longer apply to macOS targets.
- Rules are grouped into ten categories, and every finding has a classification (verified issue, potential issue, best-practice recommendation, manual review), a "why it matters" explanation, and an Apple documentation link.
- Suppressions in `.appstoreready.yml`, with a required reason and optional expiry, path, and target. Hiding an ERROR-level security finding always adds a visible warning. New `--config` and `--no-suppressions` options.
- Third-party dependencies are read from `Package.resolved`, `Podfile.lock`, and `Cartfile.resolved`.
- Optional Claude skill in `integrations/claude/`.

## 0.1.0

- First release: rules ASR001–ASR010, text and JSON reports, fixture projects.
