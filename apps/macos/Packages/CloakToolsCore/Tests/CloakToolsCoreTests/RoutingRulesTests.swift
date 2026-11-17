import Testing
import Foundation
@testable import CloakToolsCore

private func rule(_ field: RuleField = .host, _ value: String = "example.com", role: LinkRole = .web, name: String = "Work") -> RoutingRule {
    .init(name: name, role: role, conditions: [.init(field: field, value: value)], destinationBundleID: "com.example.Browser", destinationName: "Browser")
}
private func decide(_ raw: String, _ rules: [RoutingRule], source: String? = nil, available: Set<String> = ["com.example.Browser"], bypass: Bool = false) throws -> RuleDecision {
    RuleEngine.evaluate(try IncomingLink(raw, sourceApplication: source), rules: rules, available: available, forceChooser: bypass)
}

@Test func routingHostsUseBoundariesAndIDNA() throws {
    let exact = rule()
    for link in ["https://EXAMPLE.com/path", "http://example.com./", "https://%65xample.com/"] {
        #expect(try !decide(link, [exact]).usesChooser)
    }
    for link in ["https://sub.example.com", "https://example.com.attacker.test", "https://notexample.com", "https://example.com@attacker.test", "https://attacker.test/?host=example.com"] {
        #expect(try decide(link, [exact]).usesChooser)
    }
    let subdomains = rule(.hostAndSubdomains, "example.com")
    #expect(try !decide("https://one.two.example.com/path", [subdomains]).usesChooser)
    #expect(try !decide("https://example.com", [subdomains]).usesChooser)
    #expect(try decide("https://notexample.com", [subdomains]).usesChooser)
    #expect(try decide("https://example.com.attacker.test", [subdomains]).usesChooser)
    #expect(try !decide("https://xn--bcher-kva.example/", [rule(.host, "BÜCHER.Example.")]).usesChooser)
    #expect(try !decide("https://bücher.example/", [rule(.host, "xn--bcher-kva.example")]).usesChooser)
}

@Test func routingEncodedPathsAreLiteralAndCaseSensitive() throws {
    let path = rule(.pathPrefix, "/work/")
    #expect(try !decide("https://example.com/work/a?query=preserved#fragment", [path]).usesChooser)
    for link in ["https://example.com/workshop/", "https://example.com/Work/a", "https://example.com/work%2Fa", "https://example.com/%77ork/a"] {
        #expect(try decide(link, [path]).usesChooser)
    }
    #expect(try !decide("https://example.com/workshop", [rule(.pathPrefix, "/work")]).usesChooser)
    #expect(try !decide("https://example.com/a%2fb", [rule(.pathPrefix, "/a%2F")]).usesChooser)
    #expect(try decide("https://example.com/a/b", [rule(.pathPrefix, "/a%2F")]).usesChooser)
    #expect(try !decide("https://example.com", [rule(.pathPrefix, "/")]).usesChooser)
}

@Test func routingAllAnyRoleAndUnknownSource() throws {
    var all = rule()
    all.conditions += [.init(field: .scheme, value: "https"), .init(field: .sourceApplication, value: "com.example.Source")]
    #expect(try decide("https://example.com", [all]).usesChooser)
    #expect(try !decide("https://example.com", [all], source: "com.example.Source").usesChooser)
    #expect(try decide("http://example.com", [all], source: "com.example.Source").usesChooser)
    all.mode = .any
    #expect(try !decide("http://example.com", [all]).usesChooser)
    #expect(try decide("http://other.example", [all]).usesChooser)
    #expect(try !decide("http://other.example", [all], source: "com.example.Source").usesChooser)
    #expect(try decide("mailto:hello@example.com", [all], source: "com.example.Source").usesChooser)
}

@Test func routingPriorityDisabledAndMissingDestination() throws {
    var first = rule(name: "First"); let second = rule(name: "Second")
    #expect(try decide("https://example.com", [first, second]).rule?.id == first.id)
    #expect(try decide("https://example.com", [second, first]).rule?.id == second.id)
    first.enabled = false
    #expect(try decide("https://example.com", [first, second]).rule?.id == second.id)
    first.enabled = true; first.destinationBundleID = "com.example.Missing"
    let missing = try decide("https://example.com", [first, second])
    #expect(missing.usesChooser && missing.rule?.id == first.id)
    #expect(missing.reason.contains("unavailable") && missing.reason.contains("Rule 1"))
    let bypass = try decide("https://example.com", [first, second], bypass: true)
    #expect(bypass.usesChooser && bypass.rule == nil && bypass.reason.contains("bypassed"))
}

@Test func routingMailOnlyMatchesPlainToAddresses() throws {
    let mail = rule(.recipientDomain, "company.example", role: .email)
    for link in ["mailto:person@company.example", "mailto:other@personal.example,person@company.example", "mailto:?to=person%40company.example", "mailto:person%2Btag@COMPANY.example?subject=Hello%20World&body=one%0Atwo"] {
        #expect(try !decide(link, [mail]).usesChooser)
    }
    for link in ["mailto:person@sub.company.example", "mailto:person@company.example.attacker.test", "mailto:person@elsewhere.example?cc=person@company.example", "mailto:?bcc=person@company.example", "mailto:person@elsewhere.example?body=person@company.example", "mailto:Name%20%3Cperson@company.example%3E", "mailto:%22quoted%20name%22@company.example", "mailto:person@company.example,bad", "mailto://person@company.example"] {
        #expect(try decide(link, [mail]).usesChooser)
    }
    #expect(try decide("https://company.example", [mail]).usesChooser)
}

@Test func routingPreservesOriginalWithoutReadingOrRewriting() throws {
    let raw = "https://example.com/work/%2f?token=a%26b&token=c+d#fragment"
    let link = try IncomingLink(raw)
    let before = link.url.absoluteString
    let result = RuleEngine.evaluate(link, rules: [rule()], available: ["com.example.Browser"])
    #expect(!result.usesChooser && link.original == raw && link.url.absoluteString == before)
    #expect(!result.reason.contains("token"))
    let mail = try IncomingLink("mailto:one@example.com?subject=one%20two&body=Hello%0AWorld&cc=two@example.com")
    _ = RuleEngine.evaluate(mail, rules: [rule(.scheme, "mailto", role: .email)], available: ["com.example.Browser"])
    #expect(mail.original == mail.url.absoluteString)
}

@Test func routingRejectsAmbiguousOrUnsafeConditions() throws {
    for host in ["", "https://example.com", "example.com:80", "*.example.com", "example.com/path", "example..com", "-example.com", "example.com..", "example.com@elsewhere", "[::1]", "a b.example", "%65xample.com"] {
        #expect(throws: RuleError.self) { try rule(.host, host).validate() }
    }
    for path in ["work", "/work space", "/x?query", "/x#fragment", "/x%", "/x%2Z", "/日本語", "/x\\y"] {
        #expect(throws: RuleError.self) { try rule(.pathPrefix, path).validate() }
    }
    #expect(throws: RuleError.self) { try rule(.scheme, "mailto").validate() }
    #expect(throws: RuleError.self) { try rule(.host, "example.com", role: .email).validate() }
    #expect(throws: RuleError.self) { try rule(.sourceApplication, "Unknown source").validate() }
    var invalid = rule(); invalid.conditions = []
    #expect(throws: RuleError.self) { try invalid.validate() }
    #expect(try decide("https://example.com", [invalid]).usesChooser)
    invalid = rule(); invalid.destinationBundleID = "com.cloakyard.cloaktools"
    #expect(throws: RuleError.self) { try invalid.validate() }
    invalid.destinationBundleID = "com.cloakyard.cloaktools.finder"
    #expect(throws: RuleError.self) { try invalid.validate() }
}

@Test func routingStoreRoundTripValidationAndCorruption() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CloakToolsRules-\(UUID())")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = RoutingRuleStore(url: directory.appendingPathComponent("rules.json"))
    #expect(try store.load().isEmpty)
    let rules = [rule(), rule(.recipientDomain, "example.com", role: .email)]
    try store.save(rules)
    #expect(try store.load() == rules)
    let saved = try Data(contentsOf: store.url)
    #expect(throws: RuleError.self) { try store.save([rules[0], rules[0]]) }
    #expect(throws: RuleError.self) { try store.save((0..<65).map { rule(name: "Rule \($0)") }) }
    #expect(try Data(contentsOf: store.url) == saved)
    try Data("{\"version\":2,\"rules\":[]}".utf8).write(to: store.url)
    #expect(throws: RuleError.self) { try store.load() }
    try Data("{broken".utf8).write(to: store.url)
    #expect(throws: (any Error).self) { try store.load() }
    try Data(repeating: 32, count: RoutingRuleStore.maximumBytes + 1).write(to: store.url)
    #expect(throws: RuleError.self) { try store.load() }
}

@Test func routingSnapshotIsIndependentOfLaterEdits() throws {
    var rules = [rule()]
    let snapshot = rules
    rules[0].enabled = false; rules[0].conditions[0].value = "other.example"
    #expect(try !decide("https://example.com", snapshot).usesChooser)
    #expect(try decide("https://example.com", rules).usesChooser)
    #expect(try decide("https://example.com", []).usesChooser)
}
