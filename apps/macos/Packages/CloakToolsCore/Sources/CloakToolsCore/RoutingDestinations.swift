import Foundation

/// A saved app identity, not a browser profile, account, executable path or URL.
public struct DestinationReference: Codable, Equatable, Sendable, Identifiable {
    public var bundleID: String
    public var name: String
    public var id: String { bundleID }
    public init(bundleID: String, name: String) { self.bundleID = bundleID; self.name = name }
    public func validate() throws {
        guard RuleCondition.validBundleID(bundleID), bundleID != "com.cloakyard.cloaktools",
              !bundleID.hasPrefix("com.cloakyard.cloaktools."), !name.isEmpty, name.count <= 128,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw RuleError.invalid("Choose a named destination app other than CloakTools.")
        }
    }
}

public struct DestinationPreferences: Codable, Equatable, Sendable {
    public var pinned: [DestinationReference]
    public var fallback: DestinationReference?
    public init(pinned: [DestinationReference] = [], fallback: DestinationReference? = nil) {
        self.pinned = pinned; self.fallback = fallback
    }
    public func validate() throws {
        guard pinned.count <= 32, Set(pinned.map(\.bundleID)).count == pinned.count else {
            throw RuleError.invalid("Keep up to 32 distinct pinned apps per link type.")
        }
        for app in pinned { try app.validate() }
        try fallback?.validate()
    }
    /// Pins affect presentation only. Unavailable pins never enter the compatible app list.
    public func ordered(_ available: [DestinationReference]) -> [DestinationReference] {
        var positions: [String: Int] = [:]
        for (index, app) in pinned.enumerated() where positions[app.bundleID] == nil { positions[app.bundleID] = index }
        return available.enumerated().sorted {
            let left = positions[$0.element.bundleID] ?? Int.max
            let right = positions[$1.element.bundleID] ?? Int.max
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }
}

public struct RoutingDestinations: Codable, Equatable, Sendable {
    public var web: DestinationPreferences
    public var email: DestinationPreferences
    public init(web: DestinationPreferences = .init(), email: DestinationPreferences = .init()) {
        self.web = web; self.email = email
    }
    public subscript(role: LinkRole) -> DestinationPreferences {
        get { role == .web ? web : email }
        set { if role == .web { web = newValue } else { email = newValue } }
    }
    public func validate() throws { try web.validate(); try email.validate() }
}

public struct RoutingConfiguration: Equatable, Sendable {
    public let rules: [RoutingRule]
    public let destinations: RoutingDestinations
    public init(rules: [RoutingRule], destinations: RoutingDestinations) { self.rules = rules; self.destinations = destinations }
    public func evaluate(_ link: IncomingLink, available: Set<String>, forceChooser: Bool = false) -> RuleDecision {
        RuleEngine.evaluate(link, rules: rules, available: available, forceChooser: forceChooser, fallback: destinations[link.role].fallback)
    }
}

public struct RoutingDestinationStore: Sendable {
    public let url: URL
    public static let maximumBytes = 65_536
    public init(url: URL) { self.url = url }
    public static var standard: Self { .init(url: PreferencesStore.standard.url.deletingLastPathComponent().appendingPathComponent("routing-destinations.json")) }
    private struct Archive: Codable { var version = 1; let destinations: RoutingDestinations }
    public func load() throws -> RoutingDestinations {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let bytes = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
        guard bytes.count <= Self.maximumBytes else { throw RuleError.invalid("The destination settings file is too large.") }
        let archive = try JSONDecoder().decode(Archive.self, from: bytes)
        guard archive.version == 1 else { throw RuleError.invalid("This destination settings version is not supported by this app.") }
        try archive.destinations.validate(); return archive.destinations
    }
    public func save(_ destinations: RoutingDestinations) throws {
        try destinations.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(Archive(destinations: destinations))
        guard bytes.count <= Self.maximumBytes else { throw RuleError.invalid("The destination settings file is too large.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }
    /// Reject stale edits to this role and retain newer edits to the other role.
    public func save(_ preferences: DestinationPreferences, for role: LinkRole, replacing expected: DestinationPreferences) throws {
        var current = try load()
        guard current[role] == expected else { throw RuleError.invalid("These destinations changed while you were editing. Cancel and reopen to review the latest choices.") }
        current[role] = preferences
        try save(current)
    }
}
