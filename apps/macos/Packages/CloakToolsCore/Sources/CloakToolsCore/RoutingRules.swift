import Foundation

public enum RuleError: LocalizedError, Sendable {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { message } else { "Invalid rule." } }
}

public enum MatchMode: String, Codable, CaseIterable, Sendable { case all, any }
public enum RuleField: String, Codable, CaseIterable, Sendable {
    case host, hostAndSubdomains, pathPrefix, scheme, sourceApplication, recipientDomain
    public var title: String {
        switch self {
        case .host: "Host is"
        case .hostAndSubdomains: "Host or subdomain is"
        case .pathPrefix: "Path begins with"
        case .scheme: "Scheme is"
        case .sourceApplication: "Source app is"
        case .recipientDomain: "To recipient domain is"
        }
    }
    public static func available(for role: LinkRole) -> [Self] {
        role == .web ? [.host, .hostAndSubdomains, .pathPrefix, .scheme, .sourceApplication] : [.recipientDomain, .scheme, .sourceApplication]
    }
    public var hint: String {
        switch self {
        case .host, .hostAndSubdomains: "example.com"
        case .pathPrefix: "/work/"
        case .scheme: "https"
        case .sourceApplication: "com.example.app"
        case .recipientDomain: "company.example"
        }
    }
}

public struct RuleCondition: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var field: RuleField
    public var value: String
    public init(id: UUID = UUID(), field: RuleField = .host, value: String = "") {
        self.id = id; self.field = field; self.value = value
    }
    public func validate(for role: LinkRole) throws {
        guard RuleField.available(for: role).contains(field), !value.isEmpty, value.utf8.count <= 2048,
              value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw RuleError.invalid("Enter a valid value for every condition.")
        }
        switch field {
        case .host, .hostAndSubdomains, .recipientDomain:
            guard Self.canonicalHost(value) != nil else { throw RuleError.invalid("Enter a hostname, such as example.com, without a scheme, port, path or wildcard.") }
        case .pathPrefix:
            guard value.hasPrefix("/"), !value.contains("?"), !value.contains("#"), Self.encodedPath(value) != nil else {
                throw RuleError.invalid("Use a URL-encoded path starting with /. Encode spaces as %20; leave out the query and fragment.")
            }
        case .scheme:
            guard (role == .web ? ["http", "https"] : ["mailto"]).contains(value.lowercased()) else {
                throw RuleError.invalid(role == .web ? "Use http or https for a web rule." : "Use mailto for an email rule.")
            }
        case .sourceApplication:
            guard Self.validBundleID(value) else { throw RuleError.invalid("Enter the source app’s bundle identifier, such as com.example.app.") }
        }
    }
    public static func validBundleID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255 && value.contains(".") && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 46
        }
    }
    /// Foundation supplies IDNA; label validation rejects URL syntax, wildcards and ambiguous input.
    public static func canonicalHost(_ value: String) -> String? {
        guard !value.isEmpty, !value.contains(where: { "/:@?#%[]\\".contains($0) || $0.isWhitespace }),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        var host = value.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        var parts = URLComponents(); parts.scheme = "https"; parts.host = host
        guard let ascii = parts.encodedHost?.lowercased(), ascii.utf8.count <= 253 else { return nil }
        let labels = ascii.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" && label.utf8.allSatisfy {
                (48...57).contains($0) || (97...122).contains($0) || $0 == 45
            }
        }) else { return nil }
        return ascii
    }
    /// Literal, case-sensitive encoded path prefix; only hex digit case is normalized.
    static func encodedPath(_ value: String) -> String? {
        let bytes = Array(value.utf8); var result = ""; var index = 0
        let hex: (UInt8) -> Bool = { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
        while index < bytes.count {
            let byte = bytes[index]
            guard (33...126).contains(byte), byte != 92 else { return nil }
            if byte == 37 {
                guard index + 2 < bytes.count, hex(bytes[index + 1]), hex(bytes[index + 2]) else { return nil }
                result += String(decoding: bytes[index...index + 2], as: UTF8.self).uppercased(); index += 3
            } else { result.append(Character(UnicodeScalar(byte))); index += 1 }
        }
        return result
    }
    public func matches(_ link: IncomingLink) -> Bool {
        guard let parts = URLComponents(url: link.url, resolvingAgainstBaseURL: false) else { return false }
        switch field {
        case .host, .hostAndSubdomains:
            guard link.role == .web, let rawHost = parts.host, let host = Self.canonicalHost(rawHost), let expected = Self.canonicalHost(value) else { return false }
            return host == expected || (field == .hostAndSubdomains && host.hasSuffix("." + expected))
        case .pathPrefix:
            guard link.role == .web, let path = Self.encodedPath(parts.percentEncodedPath.isEmpty ? "/" : parts.percentEncodedPath), let prefix = Self.encodedPath(value) else { return false }
            return path.hasPrefix(prefix)
        case .scheme: return parts.scheme?.lowercased() == value.lowercased()
        case .sourceApplication: return link.sourceApplication == value
        case .recipientDomain:
            guard link.role == .email, let expected = Self.canonicalHost(value) else { return false }
            return Self.recipientDomains(parts).contains(expected)
        }
    }
    /// Only plain To addresses, including the `to` query field. Never inspect cc/bcc/subject/body.
    /// Ambiguous or unsupported address syntax fails closed, without changing the incoming URL.
    private static func recipientDomains(_ parts: URLComponents) -> [String] {
        guard parts.host == nil, parts.fragment == nil, let path = parts.percentEncodedPath.removingPercentEncoding else { return [] }
        let lists = [path] + (parts.queryItems ?? []).filter { $0.name.lowercased() == "to" }.compactMap(\.value)
        var domains: [String] = []
        for list in lists where !list.isEmpty {
            for address in list.split(separator: ",", omittingEmptySubsequences: false) {
                let pieces = address.split(separator: "@", omittingEmptySubsequences: false)
                guard pieces.count == 2, !pieces[0].isEmpty,
                      pieces[0].allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "!#$%&'*+-/=?^_`{|}~.".contains($0)) }),
                      !pieces[0].hasPrefix("."), !pieces[0].hasSuffix("."), !pieces[0].contains(".."),
                      let domain = canonicalHost(String(pieces[1])) else { return [] }
                domains.append(domain)
            }
        }
        return domains
    }
}

public struct RoutingRule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var role: LinkRole
    public var mode: MatchMode
    public var conditions: [RuleCondition]
    public var destinationBundleID: String
    public var destinationName: String
    public init(id: UUID = UUID(), name: String = "", enabled: Bool = true, role: LinkRole = .web, mode: MatchMode = .all,
                conditions: [RuleCondition] = [.init()], destinationBundleID: String = "", destinationName: String = "") {
        self.id = id; self.name = name; self.enabled = enabled; self.role = role; self.mode = mode
        self.conditions = conditions; self.destinationBundleID = destinationBundleID; self.destinationName = destinationName
    }
    public func validate() throws {
        guard !name.isEmpty, name.count <= 80, name == name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw RuleError.invalid("Use a rule name of 1–80 characters without control characters.") }
        guard RuleCondition.validBundleID(destinationBundleID), destinationBundleID != "com.cloakyard.cloaktools",
              !destinationBundleID.hasPrefix("com.cloakyard.cloaktools."), !destinationName.isEmpty, destinationName.count <= 128,
              !destinationName.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw RuleError.invalid("Choose a destination app other than CloakTools.") }
        guard (1...8).contains(conditions.count), Set(conditions.map(\.id)).count == conditions.count else { throw RuleError.invalid("Use 1–8 conditions per rule.") }
        for condition in conditions { try condition.validate(for: role) }
    }
    public var summary: String { "\(role == .web ? "Web" : "Email") · \(conditions.count) \(conditions.count == 1 ? "condition" : "conditions") · Match \(mode.rawValue)" }
}

public struct RuleDecision: Equatable, Sendable {
    public let rule: RoutingRule?
    public let destinationBundleID: String?
    public let reason: String
    public let fallback: DestinationReference?
    public var destinationName: String? { rule?.destinationName ?? fallback?.name }
    public var usesChooser: Bool { destinationBundleID == nil }
    public init(rule: RoutingRule?, destinationBundleID: String?, reason: String, fallback: DestinationReference? = nil) {
        self.rule = rule; self.destinationBundleID = destinationBundleID; self.reason = reason; self.fallback = fallback
    }
}

public enum RuleEngine {
    /// Pure evaluation. Availability is supplied by the host; no I/O or dispatch here.
    public static func evaluate(_ link: IncomingLink, rules: [RoutingRule], available: Set<String>, forceChooser: Bool = false, fallback: DestinationReference? = nil) -> RuleDecision {
        if forceChooser { return .init(rule: nil, destinationBundleID: nil, reason: "Choose an app for this link. Rules and fallback are bypassed for this one opening.") }
        for (index, rule) in rules.enumerated() where rule.enabled && rule.role == link.role {
            guard (try? rule.validate()) != nil else { return .init(rule: nil, destinationBundleID: nil, reason: "A routing rule is invalid. Review your rules before automatic routing resumes.") }
            let matches = rule.conditions.map { $0.matches(link) }
            guard rule.mode == .all ? matches.allSatisfy({ $0 }) : matches.contains(true) else { continue }
            let reasons = zip(rule.conditions, matches).filter(\.1).map { "\($0.0.field.title) \($0.0.value)" }.joined(separator: "; ")
            let explanation = "Rule \(index + 1), “\(rule.name)”: \(reasons)."
            guard available.contains(rule.destinationBundleID) else {
                return .init(rule: rule, destinationBundleID: nil, reason: explanation + " \(rule.destinationName) is unavailable for this link. Choose another app.")
            }
            return .init(rule: rule, destinationBundleID: rule.destinationBundleID, reason: explanation)
        }
        if let fallback {
            guard (try? fallback.validate()) != nil else {
                return .init(rule: nil, destinationBundleID: nil, reason: "The fallback app is invalid. Review your destinations before automatic routing resumes.")
            }
            guard available.contains(fallback.bundleID) else {
                return .init(rule: nil, destinationBundleID: nil, reason: "No enabled rule matched. Your fallback app, \(fallback.name), is unavailable for this link. Choose another app.", fallback: fallback)
            }
            return .init(rule: nil, destinationBundleID: fallback.bundleID, reason: "No enabled rule matched. Use your \(link.role == .web ? "web" : "email") fallback, \(fallback.name).", fallback: fallback)
        }
        return .init(rule: nil, destinationBundleID: nil, reason: "No enabled rule matched. Choose an app when the link arrives.")
    }
}

public struct RoutingRuleStore: Sendable {
    public let url: URL
    public static let maximumRules = 64
    public static let maximumBytes = 524_288
    public init(url: URL) { self.url = url }
    public static var standard: Self { .init(url: PreferencesStore.standard.url.deletingLastPathComponent().appendingPathComponent("routing-rules.json")) }
    private struct Archive: Codable { var version = 1; var rules: [RoutingRule] }
    public func load() throws -> [RoutingRule] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let bytes = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard bytes.count <= Self.maximumBytes else { throw RuleError.invalid("The routing rules file is too large.") }
        let archive = try JSONDecoder().decode(Archive.self, from: bytes)
        guard archive.version == 1 else { throw RuleError.invalid("This routing rules version is not supported by this app.") }
        try validate(archive.rules); return archive.rules
    }
    public func save(_ rules: [RoutingRule]) throws {
        try validate(rules)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(Archive(rules: rules))
        guard bytes.count <= Self.maximumBytes else { throw RuleError.invalid("The routing rules file is too large.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }
    private func validate(_ rules: [RoutingRule]) throws {
        guard rules.count <= Self.maximumRules, Set(rules.map(\.id)).count == rules.count else { throw RuleError.invalid("Keep up to 64 uniquely identified routing rules.") }
        for rule in rules { try rule.validate() }
    }
}
