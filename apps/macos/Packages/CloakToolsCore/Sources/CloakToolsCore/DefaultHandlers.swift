import Foundation

public enum LinkScheme: String, Codable, CaseIterable, Sendable, Identifiable {
    case https, http, mailto
    public var id: String { rawValue }
    public var title: String { self == .mailto ? "Email" : rawValue.uppercased() }
    public var probeURL: URL { URL(string: self == .mailto ? "mailto:hello@example.com" : "\(rawValue)://example.com/")! }
    public static func schemes(for role: LinkRole) -> [Self] { role == .web ? [.https, .http] : [.mailto] }
}

/// An installed application identity, not an account, profile or arbitrary URL handler string.
public struct HandlerApplication: Codable, Equatable, Sendable, Identifiable {
    public let bundleID: String
    public let name: String
    public let url: URL
    public var id: URL { url }
    public init(bundleID: String, name: String, url: URL) {
        self.bundleID = bundleID; self.name = name; self.url = url.standardizedFileURL
    }
    public func isSameApplication(as other: Self) -> Bool {
        bundleID == other.bundleID && url.standardizedFileURL == other.url.standardizedFileURL
    }
    public func validate() throws {
        guard RuleCondition.validBundleID(bundleID), !name.isEmpty, name.count <= 256,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              url.isFileURL, url.host == nil || url.host == "" || url.host == "localhost",
              url.path.hasPrefix("/"), url.path.utf8.count < 4096, !url.path.contains("\0"),
              url.query == nil, url.fragment == nil, url.user == nil, url.password == nil, url.port == nil else {
            throw DefaultHandlerError.invalidHistory
        }
    }
}

public struct HandlerRestorePoint: Codable, Equatable, Sendable {
    public let scheme: LinkScheme
    public let previous: HandlerApplication?
    public let owner: HandlerApplication
    public init(scheme: LinkScheme, previous: HandlerApplication?, owner: HandlerApplication) {
        self.scheme = scheme; self.previous = previous; self.owner = owner
    }
}

public enum DefaultHandlerError: LocalizedError, Sendable {
    case invalidHistory, busy, staleReview, unavailable, emptyPlan
    public var errorDescription: String? {
        switch self {
        case .invalidHistory: "The saved default-app recovery information could not be read. Your system defaults have not been changed by this request."
        case .busy: "Finish the current default-app change first."
        case .staleReview: "Your default apps changed after this review opened. Review the current apps before trying again."
        case .unavailable: "A selected app is no longer available for this link type. Refresh the review and choose an available app."
        case .emptyPlan: "There are no default apps to change."
        }
    }
}

public protocol HandlerHistoryStorage: Sendable {
    func load() throws -> [HandlerRestorePoint]
    func save(_ points: [HandlerRestorePoint]) throws
}

public struct HandlerHistoryStore: HandlerHistoryStorage {
    public let url: URL
    public init(url: URL) { self.url = url }
    public static var standard: Self { .init(url: PreferencesStore.standard.url.deletingLastPathComponent().appendingPathComponent("default-handlers.json")) }
    private struct Archive: Codable { var version = 1; var points: [HandlerRestorePoint] }
    public func load() throws -> [HandlerRestorePoint] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let bytes = try file.read(upToCount: 65_537) ?? Data()
        guard bytes.count <= 65_536 else { throw DefaultHandlerError.invalidHistory }
        let archive = try JSONDecoder().decode(Archive.self, from: bytes)
        guard archive.version == 1 else { throw DefaultHandlerError.invalidHistory }
        try validate(archive.points); return archive.points
    }
    public func save(_ points: [HandlerRestorePoint]) throws {
        try validate(points)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(Archive(points: points))
        guard bytes.count <= 65_536 else { throw DefaultHandlerError.invalidHistory }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: url, options: .atomic)
    }
    private func validate(_ points: [HandlerRestorePoint]) throws {
        guard points.count <= 3, Set(points.map(\.scheme)).count == points.count else { throw DefaultHandlerError.invalidHistory }
        for point in points {
            try point.owner.validate(); try point.previous?.validate()
            guard point.owner.bundleID == "com.cloakyard.cloaktools",
                  point.previous?.bundleID != "com.cloakyard.cloaktools" else { throw DefaultHandlerError.invalidHistory }
        }
    }
}

@MainActor public protocol DefaultHandlerSystem: AnyObject {
    func current(for scheme: LinkScheme) -> HandlerApplication?
    func available(for scheme: LinkScheme) -> [HandlerApplication]
    func set(_ application: HandlerApplication, for scheme: LinkScheme) async throws
}

public enum DefaultChangeKind: Equatable, Sendable { case useCloakTools, restore }
public struct HandlerObservation: Equatable, Sendable {
    public let scheme: LinkScheme
    public let application: HandlerApplication?
}
public struct DefaultChangeStep: Sendable {
    public let scheme: LinkScheme
    public let previous: HandlerApplication?
    public let destination: HandlerApplication
}
public struct DefaultChangePlan: Sendable {
    public let role: LinkRole
    public let kind: DefaultChangeKind
    public let observations: [HandlerObservation]
    public let steps: [DefaultChangeStep]
    fileprivate let history: [HandlerRestorePoint]
}
public struct DefaultChangeResult: Sendable {
    public let observations: [HandlerObservation]
    public let complete: Bool
    public let message: String
    public init(observations: [HandlerObservation], complete: Bool, message: String) {
        self.observations = observations; self.complete = complete; self.message = message
    }
}

/// All system writes pass through one serial, reviewed transaction. No default changes on init/refresh.
@MainActor public final class DefaultHandlerCoordinator {
    public let ownApplication: HandlerApplication
    public private(set) var busy = false
    private let system: any DefaultHandlerSystem
    private let store: any HandlerHistoryStorage
    public init(ownApplication: HandlerApplication, system: any DefaultHandlerSystem, store: any HandlerHistoryStorage) {
        self.ownApplication = ownApplication; self.system = system; self.store = store
    }
    public func observations(for role: LinkRole) -> [HandlerObservation] {
        LinkScheme.schemes(for: role).map { .init(scheme: $0, application: system.current(for: $0)) }
    }
    public func history() throws -> [HandlerRestorePoint] { try store.load() }
    public func isOwned(_ application: HandlerApplication?) -> Bool {
        application?.isSameApplication(as: ownApplication) == true
    }
    public func alternatives(for scheme: LinkScheme) -> [HandlerApplication] {
        system.available(for: scheme).filter { $0.bundleID != ownApplication.bundleID && !$0.bundleID.hasPrefix(ownApplication.bundleID + ".") }
    }
    public func previousAvailable(for scheme: LinkScheme, points: [HandlerRestorePoint]) -> HandlerApplication? {
        guard let previous = points.first(where: { $0.scheme == scheme })?.previous else { return nil }
        let apps = alternatives(for: scheme)
        return apps.first { $0.isSameApplication(as: previous) } ?? apps.first { $0.bundleID == previous.bundleID }
    }
    public func prepare(role: LinkRole, kind: DefaultChangeKind, restoring destinations: [LinkScheme: HandlerApplication] = [:]) throws -> DefaultChangePlan {
        guard !busy else { throw DefaultHandlerError.busy }
        let current = observations(for: role), history = try store.load()
        let steps = current.compactMap { observation -> DefaultChangeStep? in
            switch kind {
            case .useCloakTools:
                guard !isOwned(observation.application) else { return nil }
                return .init(scheme: observation.scheme, previous: observation.application, destination: ownApplication)
            case .restore:
                // A default changed elsewhere is deliberately excluded from the plan.
                guard isOwned(observation.application), let destination = destinations[observation.scheme] else { return nil }
                return .init(scheme: observation.scheme, previous: observation.application, destination: destination)
            }
        }
        if kind == .restore {
            guard current.filter({ isOwned($0.application) }).allSatisfy({ destinations[$0.scheme] != nil }) else { throw DefaultHandlerError.unavailable }
        }
        for step in steps {
            try step.destination.validate()
            if kind == .restore && (step.destination.bundleID == ownApplication.bundleID || step.destination.bundleID.hasPrefix(ownApplication.bundleID + ".")) {
                throw DefaultHandlerError.unavailable
            }
            guard system.available(for: step.scheme).contains(where: { $0.isSameApplication(as: step.destination) }) else { throw DefaultHandlerError.unavailable }
        }
        return .init(role: role, kind: kind, observations: current, steps: steps, history: history)
    }
    public func execute(_ plan: DefaultChangePlan) async throws -> DefaultChangeResult {
        guard !busy else { throw DefaultHandlerError.busy }
        guard !plan.steps.isEmpty else { throw DefaultHandlerError.emptyPlan }
        guard Self.same(observations(for: plan.role), plan.observations), try store.load() == plan.history else { throw DefaultHandlerError.staleReview }
        for step in plan.steps {
            guard system.available(for: step.scheme).contains(where: { $0.isSameApplication(as: step.destination) }) else { throw DefaultHandlerError.unavailable }
        }
        busy = true; defer { busy = false }
        var saved = plan.history
        if plan.kind == .useCloakTools {
            for step in plan.steps {
                // Capture the entire role before the first async request: macOS may couple HTTP/HTTPS.
                // Another CloakTools copy is never a useful restore destination.
                let previous = step.previous?.bundleID == ownApplication.bundleID ? nil : step.previous
                saved.removeAll { $0.scheme == step.scheme }
                saved.append(.init(scheme: step.scheme, previous: previous, owner: ownApplication))
            }
            try store.save(saved) // Failure here must prevent every system write.
        }
        var failure: String?
        var expected = plan.observations
        for step in plan.steps {
            guard (try? store.load()) == saved else { failure = "Recovery information changed during this request. Further changes were stopped; the newer record was kept."; break }
            let current = observations(for: plan.role)
            guard Self.same(current, expected) else { failure = "A default changed while this request was in progress. Further changes were stopped. Review the current apps."; break }
            if Self.same(system.current(for: step.scheme), step.destination) { continue }
            guard system.available(for: step.scheme).contains(where: { $0.isSameApplication(as: step.destination) }) else {
                failure = DefaultHandlerError.unavailable.localizedDescription; break
            }
            do { try await system.set(step.destination, for: step.scheme) }
            catch {
                failure = "macOS did not complete the \(step.scheme.title) request: \(error.localizedDescription)"; break
            }
            guard Self.same(system.current(for: step.scheme), step.destination) else {
                failure = "macOS did not confirm the \(step.scheme.title) change. Further changes were stopped."; break
            }
            let after = observations(for: plan.role)
            // Accept OS-coupled changes only when they equal the reviewed destination.
            guard expected.allSatisfy({ original in
                let now = after.first { $0.scheme == original.scheme }?.application
                if Self.same(now, original.application) { return true }
                return plan.steps.first(where: { $0.scheme == original.scheme }).map { Self.same(now, $0.destination) } ?? false
            }) else { failure = "Another default changed during the macOS request. Further changes were stopped. Review the current apps."; break }
            expected = after
        }
        let actual = observations(for: plan.role)
        let complete = plan.observations.allSatisfy { original in
            let destination = plan.steps.first { $0.scheme == original.scheme }?.destination ?? original.application
            return Self.same(actual.first { $0.scheme == original.scheme }?.application, destination)
        }
        // Keep recovery points for schemes still owned, including a change completed just before a crash.
        // Points for another role are never modified by this transaction.
        var cleaned = saved
        cleaned.removeAll { point in
            LinkScheme.schemes(for: plan.role).contains(point.scheme) && !isOwned(system.current(for: point.scheme))
        }
        do {
            guard try store.load() == saved else { throw DefaultHandlerError.staleReview }
            try store.save(cleaned)
        }
        catch {
            failure = (failure.map { $0 + " " } ?? "") + "The recovery record could not be updated. The current defaults shown below are the system’s actual values."
        }
        let message = failure ?? (complete ? (plan.kind == .useCloakTools ? "Matching links will now arrive in CloakTools. Your chooser and rules decide where they open." : "The selected apps are restored. Other defaults were left as they were.") : "Some defaults did not change. Review the current apps before trying again.")
        return .init(observations: actual, complete: complete && failure == nil, message: message)
    }
    private static func same(_ lhs: HandlerApplication?, _ rhs: HandlerApplication?) -> Bool {
        switch (lhs, rhs) { case (nil, nil): true; case let (a?, b?): a.isSameApplication(as: b); default: false }
    }
    private static func same(_ lhs: [HandlerObservation], _ rhs: [HandlerObservation]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.scheme == $1.scheme && same($0.application, $1.application) }
    }
}
