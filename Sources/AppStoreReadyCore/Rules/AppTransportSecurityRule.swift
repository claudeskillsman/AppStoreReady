import Foundation

/// ASR014: App Transport Security exceptions in Info.plist.
public struct AppTransportSecurityRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR014",
        title: "App Transport Security",
        description: "Reads NSAppTransportSecurity in each target's Info.plist and reports global ATS opt-outs, per-domain exceptions that allow plain HTTP, and minimum TLS versions below 1.2.",
        rationale: "ATS exceptions weaken the security of network connections. Apple's documentation says that NSAllowsArbitraryLoads, NSAllowsArbitraryLoadsForMedia, NSAllowsArbitraryLoadsInWebContent, NSExceptionAllowsInsecureHTTPLoads, and a minimum TLS version below 1.2 each require a justification and might trigger additional App Store review.",
        category: .security,
        references: [
            Reference("NSAppTransportSecurity", "https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity"),
            Reference("NSAllowsArbitraryLoads", "https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity/nsallowsarbitraryloads"),
            Reference("NSExceptionAllowsInsecureHTTPLoads", "https://developer.apple.com/documentation/bundleresources/information-property-list/nsexceptionallowsinsecurehttploads"),
            Reference("NSExceptionMinimumTLSVersion", "https://developer.apple.com/documentation/bundleresources/information-property-list/nsexceptionminimumtlsversion"),
            Reference("Preventing insecure network connections", "https://developer.apple.com/documentation/security/preventing-insecure-network-connections"),
        ]
    )

    static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.flatMap { evaluate($0, context: context) }
    }

    private func evaluate(_ target: ResolvedTarget, context: ScanContext) -> [Finding] {
        guard let info = target.infoPlist, !info.isUnreadable else { return [] }
        let file = context.infoPlistLocation(for: target, key: "NSAppTransportSecurity")
        guard let ats = info.resolved["NSAppTransportSecurity"]?.dictionaryValue else {
            return [finding(
                "App Transport Security uses the default settings",
                message: "'\(target.name)' declares no ATS exceptions, so the system requires secure connections.",
                severity: .pass,
                confidence: .high,
                file: file,
                target: target
            )]
        }

        var findings: [Finding] = []
        if ats["NSAllowsArbitraryLoads"]?.boolValue == true {
            findings.append(finding(
                "App Transport Security is disabled globally",
                message: "'\(target.name)' sets NSAllowsArbitraryLoads to true, which turns off ATS for all connections not covered by an exception. Apple's documentation says you must supply a justification during App Store review for this setting.",
                severity: .warning,
                confidence: .high,
                classification: .potentialIssue,
                file: file,
                target: target,
                evidence: ["NSAppTransportSecurity › NSAllowsArbitraryLoads = YES"] + ["NSAllowsArbitraryLoadsForMedia", "NSAllowsArbitraryLoadsInWebContent", "NSAllowsLocalNetworking"].filter { ats[$0] != nil }.map {
                    "\($0) is also present, so iOS 10+ and macOS 10.12+ ignore NSAllowsArbitraryLoads"
                },
                fix: "Remove NSAllowsArbitraryLoads and add NSExceptionDomains entries only for the specific hosts that cannot use HTTPS. Be ready to justify any remaining exception in App Review notes."
            ))
        }
        for key in ["NSAllowsArbitraryLoadsInWebContent", "NSAllowsArbitraryLoadsForMedia"] where ats[key]?.boolValue == true {
            findings.append(finding(
                "App Transport Security relaxed for \(key == "NSAllowsArbitraryLoadsInWebContent" ? "web content" : "media")",
                message: "'\(target.name)' sets \(key) to true. Apple's documentation lists this key among the ATS exceptions that need a justification during App Store review.",
                severity: .warning,
                confidence: .high,
                classification: .potentialIssue,
                file: file,
                target: target,
                evidence: ["NSAppTransportSecurity › \(key) = YES"],
                fix: "Load this content over HTTPS and remove the exception, or prepare a justification for App Review."
            ))
        }

        let domains = ats["NSExceptionDomains"]?.dictionaryValue ?? [:]
        var insecureDomains: [String] = []
        var weakTLS: [String] = []
        for (domain, value) in domains.sorted(by: { $0.key < $1.key }) {
            guard let settings = value.dictionaryValue else { continue }
            if settings["NSExceptionAllowsInsecureHTTPLoads"]?.boolValue == true
                || settings["NSThirdPartyExceptionAllowsInsecureHTTPLoads"]?.boolValue == true,
                !Self.localHosts.contains(domain.lowercased()) {
                insecureDomains.append(domain)
            }
            let tls = (settings["NSExceptionMinimumTLSVersion"] ?? settings["NSThirdPartyExceptionMinimumTLSVersion"])?.stringValue
            if let tls, tls == "TLSv1.0" || tls == "TLSv1.1" {
                weakTLS.append("\(domain): \(tls)")
            }
        }
        if !insecureDomains.isEmpty {
            findings.append(finding(
                "App Transport Security allows plain HTTP",
                message: "'\(target.name)' allows unencrypted HTTP connections to \(insecureDomains.count) domain(s). Traffic to these hosts can be read and modified in transit, and Apple requires a justification for this exception during App Store review.",
                severity: .warning,
                confidence: .high,
                classification: .potentialIssue,
                file: file,
                target: target,
                evidence: insecureDomains.map { "NSExceptionDomains › \($0) › NSExceptionAllowsInsecureHTTPLoads = YES" },
                fix: "Serve these hosts over HTTPS and remove the exceptions, or document why they are needed."
            ))
        }
        if !weakTLS.isEmpty {
            findings.append(finding(
                "App Transport Security allows outdated TLS versions",
                message: "'\(target.name)' lowers the minimum TLS version below TLS 1.2 for some domains. Apple requires a justification for this during App Store review.",
                severity: .warning,
                confidence: .high,
                classification: .potentialIssue,
                file: file,
                target: target,
                evidence: weakTLS.map { "NSExceptionMinimumTLSVersion for \($0)" },
                fix: "Upgrade the servers to TLS 1.2 or later and remove NSExceptionMinimumTLSVersion."
            ))
        }

        if findings.isEmpty {
            findings.append(finding(
                "App Transport Security exceptions are limited",
                message: "'\(target.name)' declares NSAppTransportSecurity without global opt-outs, plain HTTP exceptions, or outdated TLS versions.",
                severity: .pass,
                confidence: .high,
                file: file,
                target: target
            ))
        }
        return findings
    }
}

/// ASR015: plain `http://` URLs in source code that ATS would block.
public struct InsecureURLRule: Rule {
    public let metadata = RuleMetadata(
        id: "ASR015",
        title: "Insecure HTTP URLs",
        description: "Finds string literals with http:// URLs in a target's Swift and Objective-C code whose host is not covered by an App Transport Security exception.",
        rationale: "With App Transport Security enabled, the system blocks plain HTTP loads made through the URL Loading System, so these requests fail at runtime; if they were allowed, the traffic would be unencrypted.",
        category: .security,
        references: [
            Reference("Preventing insecure network connections", "https://developer.apple.com/documentation/security/preventing-insecure-network-connections"),
            Reference("NSAppTransportSecurity", "https://developer.apple.com/documentation/bundleresources/information-property-list/nsapptransportsecurity"),
        ]
    )

    static let url = TextPattern(#""http://([A-Za-z0-9.\-]+)"#)
    /// Hosts that commonly appear as identifiers rather than network endpoints.
    static let ignoredHosts: Set<String> = ["localhost", "127.0.0.1", "0.0.0.0", "www.w3.org", "www.apple.com", "schemas.android.com", "example.com", "www.example.com", "example.org", "ns.adobe.com", "purl.org"]

    public init() {}

    public func evaluate(_ context: ScanContext) -> [Finding] {
        context.targets.flatMap { evaluate($0, context: context) }
    }

    private func evaluate(_ target: ResolvedTarget, context: ScanContext) -> [Finding] {
        let ats = target.infoPlist?.resolved["NSAppTransportSecurity"]?.dictionaryValue ?? [:]
        if ats["NSAllowsArbitraryLoads"]?.boolValue == true { return [] }
        let exceptions = ats["NSExceptionDomains"]?.dictionaryValue ?? [:]

        func isAllowed(_ host: String) -> Bool {
            let host = host.lowercased()
            if Self.ignoredHosts.contains(host) || host.hasSuffix(".local") || host.hasSuffix(".example") { return true }
            for (domain, value) in exceptions {
                let domain = domain.lowercased()
                let settings = value.dictionaryValue ?? [:]
                guard settings["NSExceptionAllowsInsecureHTTPLoads"]?.boolValue == true
                    || settings["NSThirdPartyExceptionAllowsInsecureHTTPLoads"]?.boolValue == true else { continue }
                if host == domain { return true }
                if settings["NSIncludesSubdomains"]?.boolValue == true, host.hasSuffix("." + domain) { return true }
            }
            return false
        }

        let (files, exact) = context.codeFiles(for: target)
        var hits: [(file: SourceFile, line: Int, host: String)] = []
        for file in files where !isTestPath(file.relativePath) {
            for (index, line) in file.lines.enumerated() where !SourceText.isCommentLine(line) {
                for match in Self.url.allMatches(in: String(line)) {
                    guard let host = match[1], !isAllowed(host) else { continue }
                    hits.append((file, index + 1, host))
                }
            }
        }
        guard let first = hits.first else {
            return [finding(
                "No insecure HTTP URLs found",
                message: "No http:// URL literals for hosts without an ATS exception were found in '\(target.name)'.",
                severity: .pass,
                confidence: .medium,
                target: target
            )]
        }
        let hosts = Array(Set(hits.map(\.host))).sorted()
        return [finding(
            "Insecure HTTP URL in source",
            message: "'\(target.name)' contains http:// URLs for \(hosts.joined(separator: ", ")). App Transport Security blocks these loads unless an exception allows them.",
            severity: .warning,
            confidence: exact ? .medium : .low,
            classification: .potentialIssue,
            file: first.file.relativePath,
            line: first.line,
            target: target,
            evidence: hits.prefix(10).map { "\($0.file.relativePath):\($0.line) http://\($0.host)" } + (hits.count > 10 ? ["… and \(hits.count - 10) more"] : []),
            fix: "Use https:// URLs. If a host cannot support HTTPS, add a narrowly scoped NSExceptionDomains entry for it."
        )]
    }
}
