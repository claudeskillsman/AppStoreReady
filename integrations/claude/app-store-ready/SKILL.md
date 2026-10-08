---
name: app-store-ready
description: Audit an Xcode app project for App Store submission problems with AppStoreReady, then explain the findings and give prioritized steps to get it App Store ready.
---

# App Store Ready

Run the AppStoreReady command-line audit on the user's Xcode project, check what it found, and turn the results into a short, prioritized plan the user can follow to get the app ready for App Store submission.

AppStoreReady is a static analyser. It reads project files only. It never builds the app, runs project scripts, or uses the network. It cannot predict App Review decisions, so never tell the user the app "will be approved" or "passes App Review".

## 1. Find the project

- Use the path the user gives. Otherwise use the current folder.
- Confirm it contains an `.xcodeproj` or `.xcworkspace`. Search one or two levels down if needed.
- If there are several apps, ask which one to audit. Otherwise scan the folder; AppStoreReady discovers the projects itself.

## 2. Get the tool

Try these in order and use the first that works:

1. `command -v appstoreready`, an installed copy.
2. An existing checkout at `~/.appstoreready/AppStoreReady`. Run `swift build -c release` there if `.build/release/appstoreready` is missing.
3. Clone and build it:
   ```sh
   git clone https://github.com/charliegkoch-design/AppStoreReady.git ~/.appstoreready/AppStoreReady
   cd ~/.appstoreready/AppStoreReady && swift build -c release
   ```
4. If the clone fails, ask the user for the folder where they unzipped AppStoreReady, and build it there.

Building needs Swift 5.9 or later (Xcode 15+ on a Mac). If `swift` is missing, tell the user to install Xcode from the App Store and stop.

Call the binary `ASR` below, for example `~/.appstoreready/AppStoreReady/.build/release/appstoreready`.

## 3. Run the audit

```sh
ASR scan "<project path>" --format json --output "$TMPDIR/appstoreready-report.json" --fail-on never
ASR rules --format json > "$TMPDIR/appstoreready-rules.json"
```

- Exit code 2 means the scan could not run. Show the error message. The usual causes are no project at that path, an unknown `--configuration`, or an invalid `.appstoreready.yml`. If it's the YAML file, help fix the line it names.
- Add `--configuration <name>` only if the user names one. By default the tool uses the scheme's Archive configuration.
- Read the JSON with a script, not by printing the whole file. You need `summary`, `findings`, and `suppressed`.

Each finding has these fields:
- `ruleID`, `title`, `severity` (ERROR, WARNING, MANUAL_REVIEW, INFO, PASS)
- `classification` (verified-issue, potential-issue, best-practice, manual-review)
- `confidence`, `file`, `line`, `target`, `evidence`
- `whyItMatters`, `suggestedFix`, `documentationURL`

## 4. Check the findings before advising

For every ERROR and WARNING, open the file and line it points to and confirm the problem is real.

- Text-matching findings can be false positives. This applies to API detection (ASR006, ASR007), secrets (ASR008), insecure URLs (ASR015), and guideline topics (ASR025). Confirm these from the code.
- If a finding is wrong, say so plainly. Offer an `.appstoreready.yml` suppression with a specific reason instead of including it in the plan.
- Treat `potential-issue` findings you could not confirm as "check this", not "fix this".
- Never print a secret value. ASR008 and ASR016 findings already redact them; keep it that way when you quote code. Describe a secret by file, line and type only.

## 5. Report back

Lead with one line: how many things must be fixed, how many need a manual check, and whether anything blocks upload. Then give these sections, leaving out any that are empty.

**Fix before submitting.** Confirmed ERRORs first, then WARNINGs. Order them by impact:
1. Upload blockers: deployment target (ASR012), invalid privacy manifest or undeclared required-reason APIs (ASR007), missing bundle ID, version or build number (ASR002 to ASR004).
2. Crashes and broken features: missing purpose strings (ASR006), HealthKit usage strings, unpermitted background tasks (ASR019), malformed entitlements (ASR018).
3. Security: secrets (ASR008), credential files (ASR016), App Transport Security exceptions (ASR014, ASR015).
4. Everything else.

Write each item as a numbered step:
- **What's wrong**, in one plain sentence.
- **Where**, as `file:line` or the target and setting.
- **How to fix it**, as the exact change: the Info.plist key and value, the build setting, or the Xcode location (for example Target › Signing & Capabilities). Use the finding's `suggestedFix` and make it specific to this project.
- **Why**, as one sentence from `whyItMatters`, with the `documentationURL` as the link.

For a hardcoded secret, the fix is always: remove it from the code, rotate it with the provider, and load it at runtime instead. It is not "move it to another file".

**Check by hand before submitting.** This is a checklist from the MANUAL_REVIEW findings. It covers App Review Guideline topics (3.1.1 in-app purchase, 4.8 sign-in, 5.1.1(v) account deletion, 2.5.4 background modes), SDK privacy manifests, App Store Connect metadata, privacy labels, and Run Script phases. Say what to look at and where.

**Nice to have.** INFO best-practice items, one line each.

**Suppressed.** If `suppressed` is not empty, or there are ASR000 findings, list what is being hidden and why. Call out any "Critical security finding suppressed" or expired suppression.

**Not checked.** One or two lines saying the audit is static. It can't see code signing identities, provisioning profiles, binary SDK behavior, real accessibility, or App Store Connect settings. Recommend testing on a device, running Accessibility Inspector, and uploading to TestFlight.

Keep it conversational. If there are more than about ten fix items, give the top ten and offer the rest.

## 6. Offer to fix

After the report, offer to make the straightforward fixes. These include Info.plist keys, `INFOPLIST_KEY_*` build settings, privacy manifest entries, entitlement values, and `.appstoreready.yml` suppressions.

- Only edit after the user says yes.
- Edit the project's own files, never `project.pbxproj` by hand unless the user agrees. Prefer `.xcconfig` or Info.plist changes, and tell the user what to change in Xcode when that is safer.
- Never invent purpose-string wording or privacy manifest reasons that misdescribe the app. Ask the user what the app actually does, or offer a draft clearly marked for them to edit.
- After making fixes, run the scan again and report what changed.

## Rules

- Only call something an Apple requirement when the finding's documentation link says so.
- Don't run `xcodebuild`, build phases, or anything from the user's project, and don't upload project files anywhere.
- A clean report means AppStoreReady found nothing. It does not mean the app is guaranteed to be accepted.
