import Foundation
import Testing
@testable import CloakToolsCore

private let browser = DestinationReference(bundleID: "com.example.Browser", name: "Browser")
private let mail = DestinationReference(bundleID: "com.example.Mail", name: "Mail")
private let work = DestinationReference(bundleID: "com.example.Work", name: "Work")
private func configuration(_ destinations: RoutingDestinations = .init(), rules: [RoutingRule] = []) -> RoutingConfiguration {
    .init(rules: rules, destinations: destinations)
}
private func workRule() -> RoutingRule {
    .init(name: "Work links", conditions: [.init(field: .host, value: "work.example")], destinationBundleID: work.bundleID, destinationName: work.name)
}

@Test func fallbackStartsWithChooserAndSeparatesWebFromEmail() throws {
    let web = try IncomingLink("https://example.com/path")
    let email = try IncomingLink("mailto:hello@example.com")
    #expect(configuration().evaluate(web, available: [browser.id]).usesChooser)
    let configured = configuration(.init(web: .init(fallback: browser), email: .init(fallback: mail)))
    for raw in ["https://example.com", "http://example.com"] {
        let decision = configured.evaluate(try IncomingLink(raw), available: [browser.id, mail.id])
        #expect(decision.destinationBundleID == browser.id && decision.destinationName == browser.name)
        #expect(decision.rule == nil && decision.fallback == browser && decision.reason.contains("web fallback"))
    }
    #expect(configured.evaluate(email, available: [browser.id, mail.id]).destinationBundleID == mail.id)
    #expect(configured.evaluate(email, available: [browser.id]).usesChooser)
}

@Test func fallbackHonorsRulePriorityAndExplicitOverride() throws {
    let configured = configuration(.init(web: .init(fallback: browser)), rules: [workRule()])
    let match = try IncomingLink("https://work.example")
    let chosen = configured.evaluate(match, available: [browser.id, work.id])
    #expect(chosen.destinationBundleID == work.id && chosen.rule != nil && chosen.fallback == nil)
    let bypass = configured.evaluate(match, available: [browser.id, work.id], forceChooser: true)
    #expect(bypass.usesChooser && bypass.rule == nil && bypass.fallback == nil && bypass.reason.contains("fallback are bypassed"))
    let unmatched = configured.evaluate(try IncomingLink("https://personal.example"), available: [browser.id, work.id])
    #expect(unmatched.destinationBundleID == browser.id && unmatched.rule == nil)
    var disabled = workRule(); disabled.enabled = false
    #expect(configuration(.init(web: .init(fallback: browser)), rules: [disabled]).evaluate(match, available: [browser.id, work.id]).destinationBundleID == browser.id)
}

@Test func fallbackNeverRescuesAnUnavailableOrInvalidMatchingRule() throws {
    let link = try IncomingLink("https://work.example")
    let missing = configuration(.init(web: .init(fallback: browser)), rules: [workRule()]).evaluate(link, available: [browser.id])
    #expect(missing.usesChooser && missing.rule != nil && missing.fallback == nil && missing.reason.contains("Work is unavailable"))
    var invalid = workRule(); invalid.conditions = []
    let rejected = configuration(.init(web: .init(fallback: browser)), rules: [invalid]).evaluate(link, available: [browser.id, work.id])
    #expect(rejected.usesChooser && rejected.reason.contains("invalid"))
}

@Test func missingOrInvalidFallbackExplainsChooserWithoutChangingLink() throws {
    let raw = "mailto:one@example.com?cc=two%40example.com&subject=a%26b&body=One%0D%0ATwo+three"
    let link = try IncomingLink(raw)
    let configured = configuration(.init(email: .init(fallback: mail)))
    let decision = configured.evaluate(link, available: [])
    #expect(decision.usesChooser && decision.fallback == mail && decision.reason.contains("unavailable"))
    #expect(link.original == raw && link.url.absoluteString == raw)
    #expect(!decision.reason.contains("subject") && !decision.reason.contains("one@example.com"))
    let unsafe = DestinationReference(bundleID: "com.cloakyard.cloaktools", name: "CloakTools")
    let invalid = configuration(.init(email: .init(fallback: unsafe))).evaluate(link, available: [unsafe.id])
    #expect(invalid.usesChooser && invalid.reason.contains("invalid"))
}

@Test func destinationPinsOrderAvailableAppsWithoutHidingOthersOrRouting() throws {
    let missing = DestinationReference(bundleID: "com.example.Gone", name: "Gone")
    let pins = DestinationPreferences(pinned: [work, missing, browser])
    #expect(pins.ordered([browser, mail, work]) == [work, browser, mail])
    #expect(pins.ordered([mail]) == [mail])
    #expect(pins.ordered([]).isEmpty)
    #expect(configuration(.init(web: pins)).evaluate(try IncomingLink("https://example.com"), available: [browser.id, work.id]).usesChooser)
    // Even direct in-memory callers cannot trigger a duplicate-key trap.
    #expect(DestinationPreferences(pinned: [work, work]).ordered([browser, work]) == [work, browser])
}

@Test func destinationSnapshotsRetainOriginalChoicesAndPinOrder() throws {
    var destinations = RoutingDestinations(web: .init(pinned: [work, browser], fallback: browser))
    let snapshot = configuration(destinations)
    destinations.web.fallback = work
    destinations.web.pinned.reverse()
    let link = try IncomingLink("https://example.com")
    #expect(snapshot.evaluate(link, available: [browser.id, work.id]).destinationBundleID == browser.id)
    #expect(snapshot.destinations.web.ordered([browser, work]) == [work, browser])
    #expect(configuration(destinations).evaluate(link, available: [browser.id, work.id]).destinationBundleID == work.id)
}

@Test func destinationStorePersistsChoicesRejectsStaleEditsAndKeepsOtherRole() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsDestinations-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = RoutingDestinationStore(url: directory.appendingPathComponent("destinations.json"))
    #expect(try store.load() == .init())
    #expect(!FileManager.default.fileExists(atPath: store.url.path))
    let original = RoutingDestinations(web: .init(pinned: [browser], fallback: browser))
    try store.save(original)
    try store.save(.init(fallback: mail), for: .email, replacing: .init())
    let updated = DestinationPreferences(pinned: [work, browser], fallback: work)
    try store.save(updated, for: .web, replacing: original.web)
    #expect(try store.load() == .init(web: updated, email: .init(fallback: mail)))
    let bytes = try Data(contentsOf: store.url)
    #expect(throws: RuleError.self) { try store.save(.init(), for: .web, replacing: original.web) }
    #expect(try Data(contentsOf: store.url) == bytes)
}

@Test func destinationStoreBoundsAndCorruptionFailClosed() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsDestinations-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = RoutingDestinationStore(url: directory.appendingPathComponent("destinations.json"))
    try store.save(.init(web: .init(pinned: [browser], fallback: browser)))
    let bytes = try Data(contentsOf: store.url)
    #expect(throws: RuleError.self) { try store.save(.init(web: .init(pinned: [browser, browser]))) }
    #expect(throws: RuleError.self) { try store.save(.init(web: .init(pinned: (0..<33).map { .init(bundleID: "com.example.App\($0)", name: "App \($0)") }))) }
    #expect(try Data(contentsOf: store.url) == bytes)
    let json = String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 2")
    try Data(json.utf8).write(to: store.url)
    #expect(throws: RuleError.self) { try store.load() }
    try Data("{broken".utf8).write(to: store.url)
    #expect(throws: (any Error).self) { try store.load() }
    try Data(repeating: 32, count: RoutingDestinationStore.maximumBytes + 1).write(to: store.url)
    #expect(throws: RuleError.self) { try store.load() }
}

@Test func destinationReferencesRejectSelfUnsafeIDsAndLabels() throws {
    for id in ["", "not a bundle", "com.cloakyard.cloaktools", "com.cloakyard.cloaktools.finder"] {
        #expect(throws: RuleError.self) { try DestinationReference(bundleID: id, name: "App").validate() }
    }
    for name in ["", "App\nName", String(repeating: "a", count: 129)] {
        #expect(throws: RuleError.self) { try DestinationReference(bundleID: browser.id, name: name).validate() }
    }
}
