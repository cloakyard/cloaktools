import Foundation
import Synchronization
import Testing
@testable import CloakToolsCore

private let cloak = HandlerApplication(bundleID: "com.cloakyard.cloaktools", name: "CloakTools", url: URL(fileURLWithPath: "/Applications/CloakTools.app"))
private let chrome = HandlerApplication(bundleID: "com.google.Chrome", name: "Chrome", url: URL(fileURLWithPath: "/Applications/Chrome.app"))
private let safari = HandlerApplication(bundleID: "com.apple.Safari", name: "Safari", url: URL(fileURLWithPath: "/Applications/Safari.app"))
private let mail = HandlerApplication(bundleID: "com.apple.mail", name: "Mail", url: URL(fileURLWithPath: "/Applications/Mail.app"))
private enum SimulatedFailure: Error { case declined, diskFull }

private final class MemoryHandlerHistory: HandlerHistoryStorage {
    private struct State: Sendable { var points: [HandlerRestorePoint]; var saves = 0; var failOnSave: Int? }
    private let state: Mutex<State>
    init(_ points: [HandlerRestorePoint] = []) { state = Mutex(State(points: points)) }
    var saves: Int { state.withLock { $0.saves } }
    func fail(on save: Int) { state.withLock { $0.failOnSave = save } }
    func load() throws -> [HandlerRestorePoint] { state.withLock { $0.points } }
    func save(_ points: [HandlerRestorePoint]) throws {
        try state.withLock {
            $0.saves += 1
            if $0.failOnSave == $0.saves { throw SimulatedFailure.diskFull }
            $0.points = points
        }
    }
}

@MainActor private final class FakeDefaultSystem: DefaultHandlerSystem {
    var values: [LinkScheme: HandlerApplication] = [.https: chrome, .http: chrome, .mailto: mail]
    var choices: [LinkScheme: [HandlerApplication]] = [.https: [cloak, chrome, safari], .http: [cloak, chrome, safari], .mailto: [cloak, mail]]
    var calls: [(LinkScheme, HandlerApplication)] = []
    var intercept: ((HandlerApplication, LinkScheme) throws -> Void)?
    var hold = false
    var started: (() -> Void)?
    var resume: CheckedContinuation<Void, Never>?
    func current(for scheme: LinkScheme) -> HandlerApplication? { values[scheme] }
    func available(for scheme: LinkScheme) -> [HandlerApplication] { choices[scheme] ?? [] }
    func set(_ application: HandlerApplication, for scheme: LinkScheme) async throws {
        calls.append((scheme, application))
        if hold {
            hold = false
            await withCheckedContinuation { resume = $0; started?() }
        }
        if let intercept { try intercept(application, scheme) }
        else { values[scheme] = application }
    }
    func coordinator(_ store: any HandlerHistoryStorage) -> DefaultHandlerCoordinator { .init(ownApplication: cloak, system: self, store: store) }
}

@Test @MainActor func defaultSetupReviewIsReadOnlyAndCapturesBothSchemesBeforeWriting() async throws {
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(), coordinator = system.coordinator(store)
    let plan = try coordinator.prepare(role: .web, kind: .useCloakTools)
    #expect(system.calls.isEmpty && store.saves == 0)
    #expect(plan.steps.map(\.scheme) == [.https, .http])
    system.intercept = { app, scheme in
        let points = try store.load()
        #expect(Set(points.map(\.scheme)) == [.https, .http])
        #expect(points.allSatisfy { $0.previous == chrome && $0.owner == cloak })
        system.values[scheme] = app
    }
    let result = try await coordinator.execute(plan)
    #expect(result.complete && system.values[.https] == cloak && system.values[.http] == cloak)
    #expect(system.values[.mailto] == mail && system.calls.map(\.0) == [.https, .http])
}

@Test @MainActor func defaultConsentDeclinedDoesNotContinueOrClaimSuccess() async throws {
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(), coordinator = system.coordinator(store)
    system.intercept = { _, _ in throw SimulatedFailure.declined }
    let result = try await coordinator.execute(coordinator.prepare(role: .web, kind: .useCloakTools))
    #expect(!result.complete && result.message.contains("HTTPS"))
    #expect(system.calls.count == 1 && system.values[.https] == chrome && system.values[.http] == chrome)
    #expect(try store.load().isEmpty)
}

@Test @MainActor func defaultPartialFailureRetryAndRestorationKeepOriginalApps() async throws {
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(), coordinator = system.coordinator(store)
    system.intercept = { app, scheme in
        if scheme == .http { throw SimulatedFailure.declined }
        system.values[scheme] = app
    }
    let partial = try await coordinator.execute(coordinator.prepare(role: .web, kind: .useCloakTools))
    #expect(!partial.complete && system.values[.https] == cloak && system.values[.http] == chrome)
    #expect(try store.load().map(\.scheme) == [.https])
    system.intercept = nil
    let retry = try coordinator.prepare(role: .web, kind: .useCloakTools)
    #expect(retry.steps.map(\.scheme) == [.http])
    #expect(try await coordinator.execute(retry).complete)
    #expect(try store.load().allSatisfy { $0.previous == chrome })
    let restore = try coordinator.prepare(role: .web, kind: .restore, restoring: [.https: chrome, .http: chrome])
    #expect(try await coordinator.execute(restore).complete)
    #expect(system.values[.https] == chrome && system.values[.http] == chrome && system.values[.mailto] == mail)
    #expect(try store.load().isEmpty)
}

@Test @MainActor func defaultCoupledWebSetupSkipsRedundantSystemRequest() async throws {
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(), coordinator = system.coordinator(store)
    system.intercept = { app, _ in
        let captured = try store.load()
        #expect(captured.count == 2)
        system.values[.https] = app; system.values[.http] = app
    }
    #expect(try await coordinator.execute(coordinator.prepare(role: .web, kind: .useCloakTools)).complete)
    #expect(system.calls.count == 1)
    #expect(try store.load().count == 2)
}

@Test @MainActor func defaultRestoreRespectsExternalChangesAndIndependentRoles() async throws {
    let points = LinkScheme.allCases.map { HandlerRestorePoint(scheme: $0, previous: $0 == .mailto ? mail : chrome, owner: cloak) }
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(points), coordinator = system.coordinator(store)
    system.values = [.https: cloak, .http: safari, .mailto: cloak]
    let plan = try coordinator.prepare(role: .web, kind: .restore, restoring: [.https: chrome, .http: chrome])
    #expect(plan.steps.map(\.scheme) == [.https])
    #expect(try await coordinator.execute(plan).complete)
    #expect(system.values[.http] == safari && system.values[.mailto] == cloak)
    #expect(try store.load().map(\.scheme) == [.mailto])
    #expect(try await coordinator.execute(coordinator.prepare(role: .email, kind: .restore, restoring: [.mailto: mail])).complete)
    #expect(system.values[.https] == chrome && system.values[.http] == safari)
}

@Test @MainActor func defaultMissingPreviousAppRequiresAnExplicitAvailableAlternative() async throws {
    let missing = HandlerApplication(bundleID: "com.example.Missing", name: "Missing Browser", url: URL(fileURLWithPath: "/Applications/Missing.app"))
    let point = HandlerRestorePoint(scheme: .https, previous: missing, owner: cloak)
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory([point]), coordinator = system.coordinator(store)
    system.values[.https] = cloak
    #expect(coordinator.previousAvailable(for: .https, points: [point]) == nil)
    #expect(throws: DefaultHandlerError.self) { try coordinator.prepare(role: .web, kind: .restore) }
    let plan = try coordinator.prepare(role: .web, kind: .restore, restoring: [.https: safari])
    #expect(try await coordinator.execute(plan).complete)
    #expect(system.values[.https] == safari && system.values[.http] == chrome)
}

@Test @MainActor func defaultMovedAppResolvesIdentityAndDisappearingTargetBlocksWrite() async throws {
    let old = HandlerApplication(bundleID: chrome.bundleID, name: chrome.name, url: URL(fileURLWithPath: "/Old/Chrome.app"))
    let points = [HandlerRestorePoint(scheme: .https, previous: old, owner: cloak)]
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(points), coordinator = system.coordinator(store)
    system.values[.https] = cloak
    #expect(coordinator.previousAvailable(for: .https, points: points) == chrome)
    let plan = try coordinator.prepare(role: .web, kind: .restore, restoring: [.https: chrome])
    system.choices[.https] = [cloak, safari]
    await #expect(throws: DefaultHandlerError.self) { try await coordinator.execute(plan) }
    #expect(system.calls.isEmpty && store.saves == 0 && system.values[.https] == cloak)
}

@Test @MainActor func defaultStaleReviewAndChangedHistoryCannotOverwriteNewChoices() async throws {
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(), coordinator = system.coordinator(store)
    let plan = try coordinator.prepare(role: .web, kind: .useCloakTools)
    system.values[.http] = safari
    await #expect(throws: DefaultHandlerError.self) { try await coordinator.execute(plan) }
    #expect(system.calls.isEmpty && store.saves == 0)
    let fresh = try coordinator.prepare(role: .web, kind: .useCloakTools)
    try store.save([.init(scheme: .mailto, previous: mail, owner: cloak)])
    await #expect(throws: DefaultHandlerError.self) { try await coordinator.execute(fresh) }
    #expect(system.calls.isEmpty)
}

@Test @MainActor func defaultUnexpectedChangesDuringConsentStopRemainingSteps() async throws {
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(), coordinator = system.coordinator(store)
    system.intercept = { app, scheme in
        system.values[scheme] = app
        system.values[.http] = safari
    }
    let result = try await coordinator.execute(coordinator.prepare(role: .web, kind: .useCloakTools))
    #expect(!result.complete && system.calls.count == 1 && system.values[.http] == safari)
    #expect(try store.load().map(\.scheme) == [.https])
}

@Test @MainActor func defaultUnconfirmedSystemSuccessDoesNotContinue() async throws {
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(), coordinator = system.coordinator(store)
    system.intercept = { _, _ in } // A callback alone is not proof of system state.
    let result = try await coordinator.execute(coordinator.prepare(role: .web, kind: .useCloakTools))
    #expect(!result.complete && result.message.contains("did not confirm"))
    #expect(system.calls.count == 1 && system.values[.http] == chrome)
}

@Test @MainActor func defaultConcurrentHistoryEditIsPreserved() async throws {
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(), coordinator = system.coordinator(store)
    system.intercept = { app, scheme in
        system.values[scheme] = app
        var points = try store.load()
        points.append(.init(scheme: .mailto, previous: mail, owner: cloak))
        try store.save(points)
    }
    let result = try await coordinator.execute(coordinator.prepare(role: .web, kind: .useCloakTools))
    #expect(!result.complete && system.calls.count == 1)
    #expect(try store.load().contains { $0.scheme == .mailto && $0.previous == mail })
    #expect(system.values[.http] == chrome)
}

@Test @MainActor func defaultPersistenceFailureBeforeAndAfterMutation() async throws {
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(), coordinator = system.coordinator(store)
    store.fail(on: 1)
    await #expect(throws: SimulatedFailure.self) { try await coordinator.execute(coordinator.prepare(role: .email, kind: .useCloakTools)) }
    #expect(system.calls.isEmpty && system.values[.mailto] == mail && !coordinator.busy)
    let secondSystem = FakeDefaultSystem(), secondStore = MemoryHandlerHistory(), second = secondSystem.coordinator(secondStore)
    secondStore.fail(on: 2)
    let result = try await second.execute(second.prepare(role: .email, kind: .useCloakTools))
    #expect(!result.complete && result.message.contains("recovery record"))
    #expect(secondSystem.values[.mailto] == cloak)
    #expect(try secondStore.load().first?.previous == mail) // The preflight recovery point survived.
}

@Test @MainActor func defaultConcurrentRequestsAreSerializedAcrossConsent() async throws {
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(), coordinator = system.coordinator(store)
    system.hold = true
    let plan = try coordinator.prepare(role: .email, kind: .useCloakTools)
    var task: Task<DefaultChangeResult, any Error>?
    await withCheckedContinuation { started in
        system.started = { started.resume() }
        task = Task { try await coordinator.execute(plan) }
    }
    #expect(coordinator.busy && system.calls.count == 1)
    #expect(throws: DefaultHandlerError.self) { try coordinator.prepare(role: .web, kind: .useCloakTools) }
    await #expect(throws: DefaultHandlerError.self) { try await coordinator.execute(plan) }
    system.resume?.resume(); system.resume = nil
    #expect(try await task?.value.complete == true)
    #expect(!coordinator.busy)
}

@Test @MainActor func defaultNoPriorAppAndOtherCopyAreNotInventedRestorePoints() async throws {
    let system = FakeDefaultSystem(), store = MemoryHandlerHistory(), coordinator = system.coordinator(store)
    system.values[.mailto] = nil
    #expect(try await coordinator.execute(coordinator.prepare(role: .email, kind: .useCloakTools)).complete)
    #expect(try store.load().first?.previous == nil)
    let noChange = try coordinator.prepare(role: .email, kind: .useCloakTools)
    #expect(noChange.steps.isEmpty)
    await #expect(throws: DefaultHandlerError.self) { try await coordinator.execute(noChange) }
    #expect(try await coordinator.execute(coordinator.prepare(role: .email, kind: .restore, restoring: [.mailto: mail])).complete)
    let other = HandlerApplication(bundleID: cloak.bundleID, name: cloak.name, url: URL(fileURLWithPath: "/Other/CloakTools.app"))
    system.values[.https] = other
    #expect(!coordinator.isOwned(other))
    #expect(try coordinator.prepare(role: .web, kind: .restore).steps.isEmpty)
}

@Test func defaultHistoryRoundTripBoundsAndCorruption() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsHandlers-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = HandlerHistoryStore(url: directory.appendingPathComponent("history.json"))
    #expect(try store.load().isEmpty)
    let point = HandlerRestorePoint(scheme: .https, previous: chrome, owner: cloak)
    try store.save([point]); #expect(try store.load() == [point])
    let saved = try Data(contentsOf: store.url)
    #expect(throws: DefaultHandlerError.self) { try store.save([point, point]) }
    #expect(throws: DefaultHandlerError.self) { try store.save([.init(scheme: .mailto, previous: cloak, owner: cloak)]) }
    #expect(throws: DefaultHandlerError.self) { try store.save([.init(scheme: .https, previous: chrome, owner: safari)]) }
    #expect(try Data(contentsOf: store.url) == saved)
    try Data("{\"version\":2,\"points\":[]}".utf8).write(to: store.url)
    #expect(throws: DefaultHandlerError.self) { try store.load() }
    try Data("{invalid".utf8).write(to: store.url)
    #expect(throws: (any Error).self) { try store.load() }
    try Data(repeating: 32, count: 65_537).write(to: store.url)
    #expect(throws: DefaultHandlerError.self) { try store.load() }
}
