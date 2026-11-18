import AppKit
import SwiftUI
import CloakToolsCore

@MainActor @Observable
final class RoutingSettings {
    var rules: [RoutingRule] = []
    var error: String?
    var showingTester = false
    var showingOneTime = false
    var destinations = RoutingDestinations()
    var destinationError: String?
    private let store = RoutingRuleStore.standard
    private let destinationStore = RoutingDestinationStore.standard
    init() { reload() }
    func reload() {
        do { rules = try store.load(); error = nil }
        catch { self.error = "Routing rules could not be read. Incoming links will use the chooser. \(error.localizedDescription)" }
        do { destinations = try destinationStore.load(); destinationError = nil }
        catch { destinationError = "Destinations could not be read. Incoming links will use the chooser. \(error.localizedDescription)" }
    }
    func snapshot() throws -> [RoutingRule] { try store.load() }
    func configuration() throws -> RoutingConfiguration { .init(rules: try store.load(), destinations: try destinationStore.load()) }
    func destinationSnapshot() throws -> RoutingDestinations { try destinationStore.load() }
    func saveDestinations(_ preferences: DestinationPreferences, for role: LinkRole, replacing expected: DestinationPreferences) throws {
        try destinationStore.save(preferences, for: role, replacing: expected)
        destinations = try destinationStore.load(); destinationError = nil
    }
    func save(_ rule: RoutingRule) throws {
        var updated = try snapshot()
        if let index = updated.firstIndex(where: { $0.id == rule.id }) { updated[index] = rule }
        else { updated.append(rule) }
        try store.save(updated); rules = updated; error = nil
    }
    func remove(_ rule: RoutingRule) { change { $0.removeAll { $0.id == rule.id } } }
    func enable(_ rule: RoutingRule, _ enabled: Bool) {
        change { if let index = $0.firstIndex(where: { $0.id == rule.id }) { $0[index].enabled = enabled } }
    }
    func move(_ rule: RoutingRule, by offset: Int) {
        change { rules in
            guard let index = rules.firstIndex(where: { $0.id == rule.id }), rules.indices.contains(index + offset) else { return }
            rules.swapAt(index, index + offset)
        }
    }
    private func change(_ edit: (inout [RoutingRule]) -> Void) {
        do { var updated = try snapshot(); edit(&updated); try store.save(updated); rules = updated; error = nil }
        catch { self.error = error.localizedDescription }
    }
    func draft(for link: IncomingLink, destination: Destination) -> RoutingRule {
        // Only an explicit hostname/scheme condition is proposed; no query, path or email body is saved.
        let host = link.role == .web ? URLComponents(url: link.url, resolvingAgainstBaseURL: false)?.host : nil
        let condition: RuleCondition = host.flatMap(RuleCondition.canonicalHost).map { .init(field: .host, value: $0) }
            ?? .init(field: .scheme, value: link.url.scheme?.lowercased() ?? "mailto")
        return .init(name: link.role == .web ? "Open in \(destination.name)" : "Email in \(destination.name)", role: link.role,
                     conditions: [condition], destinationBundleID: destination.bundleID, destinationName: destination.name)
    }
}

struct RoutingSettingsView: View {
    let model: AppModel
    @Bindable var routing: RoutingSettings
    @State private var editing: RoutingRule?
    @State private var removing: RoutingRule?
    var body: some View {
        Group {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The right app for each link.").font(.title3)
                        Text("Rules run from top to bottom. The first match wins.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Test a Link…", systemImage: "link.badge.plus") { routing.showingTester = true }
                }
                Button("Open a Link Once…", systemImage: "arrow.up.forward.app") { routing.showingOneTime = true }
                if let lastRoute = model.router.lastRoute { LabeledContent("Last opening this session", value: lastRoute) }
            }
            DefaultHandlerSection(settings: model.defaultHandlers, onRefresh: routing.reload)
            DestinationSettingsSection(routing: routing)
            Section {
                if let error = routing.error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                if routing.rules.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("No routing rules yet", systemImage: "arrow.triangle.branch").fontWeight(.medium)
                        Text("Links use your fallback choices. Add a rule for links that need a different app.").foregroundStyle(.secondary)
                    }.padding(.vertical, 5)
                }
                ForEach(Array(routing.rules.enumerated()), id: \.element.id) { index, rule in
                    HStack(spacing: 10) {
                        Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(rule.name).fontWeight(.medium).lineLimit(1)
                            Text("\(rule.summary) → \(rule.destinationName)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Toggle("Enable \(rule.name)", isOn: Binding(get: { rule.enabled }, set: { routing.enable(rule, $0) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        Menu {
                            Button("Edit Rule…") { editing = rule }
                            Button("Move Up") { routing.move(rule, by: -1) }.disabled(index == 0)
                            Button("Move Down") { routing.move(rule, by: 1) }.disabled(index == routing.rules.count - 1)
                            Divider()
                            Button("Delete Rule…", role: .destructive) { removing = rule }
                        } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Actions for \(rule.name)")
                    }.padding(.vertical, 3)
                }
                Button("Add Rule…", systemImage: "plus") { editing = RoutingRule() }
                    .disabled(routing.rules.count >= RoutingRuleStore.maximumRules || routing.error != nil)
            } header: { Text("Routing rules") } footer: {
                Text("Rules apply only to links delivered to CloakTools. An unavailable destination returns to the chooser.")
            }
            Section("Try an incoming link") {
                Button("Send a Web Link to CloakTools") { deliver("https://example.com/?from=cloaktools") }
                Button("Send an Email Link to CloakTools") { deliver("mailto:hello@example.com?subject=CloakTools%20test&body=Hello%2C%20World%21") }
                Text("These buttons deliver a real URL event and apply enabled rules. They do not change your system defaults.").foregroundStyle(.secondary)
            }
            Section {
                Text("Rules stay on this Mac. Tested and incoming links are not saved. Source identity is Unknown unless reliably supplied; it is never inferred from the frontmost app.")
                Text("An app is separate from its profiles and signed-in accounts. Email links prepare a draft; they never send mail.").foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editing) { RuleEditor(draft: $0, routing: routing) }
        .sheet(isPresented: $routing.showingTester) { LinkTester(routing: routing) }
        .sheet(isPresented: $routing.showingOneTime) { OneTimeLink(router: model.router) }
        .confirmationDialog("Delete this routing rule?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let removing { Button("Delete Rule", role: .destructive) { routing.remove(removing); self.removing = nil } }
        } message: { Text("Incoming links will use the remaining rules, then your fallback choice.") }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func refresh() {
        routing.reload()
        model.defaultHandlers.refresh()
    }
    private func deliver(_ raw: String) {
        NSWorkspace.shared.open([URL(string: raw)!], withApplicationAt: Bundle.main.bundleURL, configuration: .init()) { _, error in
            if let error { Task { @MainActor in model.showError(error) } }
        }
    }
}

struct OneTimeLink: View {
    let router: LinkRouter
    @Environment(\.dismiss) private var dismiss
    @State private var raw = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: "Open a link once", subtitle: "Choose an app, bypassing rules and fallback.", symbol: "arrow.up.forward.app")
            TextField("https://example.com or mailto:…", text: $raw, axis: .vertical)
                .lineLimit(2...3).textFieldStyle(.roundedBorder).accessibilityLabel("Link to open once")
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            GlassEffectContainer(spacing: 8) {
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                    Button("Choose App") {
                        do { _ = try IncomingLink(raw); dismiss(); router.receive(raw, forceChooser: true) }
                        catch { self.error = error.localizedDescription }
                    }.keyboardShortcut(.defaultAction).disabled(raw.isEmpty).modifier(DialogActionStyle(prominent: true))
                }
            }
        }.padding(20).frame(width: 440)
    }
}

struct RuleEditor: View {
    @State var draft: RoutingRule
    let routing: RoutingSettings
    @State private var destinations: [Destination] = []
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: "Routing rule", subtitle: "Open matching links in the app you choose.", symbol: "arrow.triangle.branch")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(spacing: 12) {
                        TextField("Rule name", text: $draft.name).textFieldStyle(.roundedBorder).accessibilityLabel("Rule name")
                        Picker("Link type", selection: $draft.role) { Text("Web").tag(LinkRole.web); Text("Email").tag(LinkRole.email) }.pickerStyle(.segmented)
                        Picker("Open in", selection: $draft.destinationBundleID) {
                            Text("Choose an app").tag("")
                            ForEach(destinations) { Text($0.name).tag($0.bundleID) }
                            if !draft.destinationBundleID.isEmpty && !destinations.contains(where: { $0.bundleID == draft.destinationBundleID }) {
                                Text("\(draft.destinationName) (unavailable)").tag(draft.destinationBundleID)
                            }
                        }
                    }.modifier(DialogCard())
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Conditions").fontWeight(.medium)
                            Spacer()
                            Picker("Match", selection: $draft.mode) { Text("All").tag(MatchMode.all); Text("Any").tag(MatchMode.any) }
                                .pickerStyle(.segmented).labelsHidden().accessibilityLabel("Match conditions").frame(width: 122)
                        }
                        ForEach($draft.conditions) { $condition in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Picker("Condition", selection: $condition.field) {
                                        ForEach(RuleField.available(for: draft.role), id: \.self) { Text($0.title).tag($0) }
                                    }.labelsHidden().accessibilityLabel("Condition type")
                                    Button { draft.conditions.removeAll { $0.id == condition.id } } label: { Image(systemName: "minus.circle") }
                                        .buttonStyle(.borderless).disabled(draft.conditions.count == 1).help("Remove condition").accessibilityLabel("Remove condition")
                                }
                                TextField(condition.field.hint, text: $condition.value).textFieldStyle(.roundedBorder)
                                    .accessibilityLabel(condition.field.title)
                            }
                        }
                        Button("Add Condition", systemImage: "plus") { draft.conditions.append(.init(field: draft.role == .web ? .host : .recipientDomain)) }
                            .buttonStyle(.borderless).disabled(draft.conditions.count >= 8)
                    }.modifier(DialogCard())
                    Text(conditionHelp).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Toggle("Enable this rule", isOn: $draft.enabled).toggleStyle(.switch).controlSize(.small)
                }
            }.scrollBounceBehavior(.basedOnSize)
            if let error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            GlassEffectContainer(spacing: 8) {
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                    Button("Save Rule") {
                        do {
                            if let app = destinations.first(where: { $0.bundleID == draft.destinationBundleID }) { draft.destinationName = app.name }
                            try routing.save(draft); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.keyboardShortcut(.defaultAction).modifier(DialogActionStyle(prominent: true))
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.destinationBundleID.isEmpty || draft.conditions.contains { $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                }
            }
        }.padding(20).frame(width: 460, height: 510)
            .onAppear(perform: refresh)
            .onChange(of: draft.role) {
                draft.conditions = [.init(field: draft.role == .web ? .host : .recipientDomain)]
                draft.destinationBundleID = ""; draft.destinationName = ""; refresh()
            }
    }
    private var conditionHelp: String {
        var text = draft.role == .web ? "Hosts match exactly unless you choose subdomains." : "Recipient domains match any plain To address, including the to field; cc, bcc and message text are ignored."
        if draft.conditions.contains(where: { $0.field == .pathPrefix }) { text += " Paths use a case-sensitive URL-encoded prefix: /work also matches /workshop; use /work/ for that folder." }
        if draft.conditions.contains(where: { $0.field == .sourceApplication }) { text += " Source uses an exact bundle ID. Unknown sources never match this condition." }
        return text
    }
    private func refresh() {
        destinations = Destination.ordered(Destination.applications(for: draft.role), preferences: (try? routing.destinationSnapshot()[draft.role]) ?? .init())
    }
}

struct LinkTester: View {
    let routing: RoutingSettings
    @Environment(\.dismiss) private var dismiss
    @State private var raw = ""
    @State private var source = ""
    @State private var bypass = false
    @State private var result: RuleDecision?
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: "Test a link", subtitle: "See where it would go. Nothing opens.", symbol: "link")
            VStack(alignment: .leading, spacing: 10) {
                Text("Web or email link").font(.caption).foregroundStyle(.secondary)
                TextField("https://example.com", text: $raw, axis: .vertical).lineLimit(2...3)
                    .textFieldStyle(.roundedBorder).accessibilityLabel("Link to test")
                TextField("Simulated source bundle ID (optional)", text: $source).textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Simulated source bundle identifier")
                Toggle("Bypass rules and fallback", isOn: $bypass).controlSize(.small)
            }.modifier(DialogCard())
            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    if let result {
                        Label(result.usesChooser ? "Show chooser" : "Open in \(result.destinationName ?? "app")", systemImage: result.usesChooser ? "list.bullet" : "arrow.up.forward.app")
                            .font(.headline)
                        Text(result.reason).font(.callout).textSelection(.enabled)
                        if !source.isEmpty { Text("Source is simulated for this test only.").font(.caption).foregroundStyle(.secondary) }
                    } else if let error { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                    else { Text("Test rules, fallback choices, and destination availability.").foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).modifier(DialogCard())
            Text("No network requests, app launches or link history.").font(.caption).foregroundStyle(.secondary)
            GlassEffectContainer(spacing: 8) {
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                    Button("Test Link", action: test).keyboardShortcut(.defaultAction).disabled(raw.isEmpty).modifier(DialogActionStyle(prominent: true))
                }
            }
        }.padding(20).frame(width: 460, height: 450)
            .onChange(of: raw) { clear() }.onChange(of: source) { clear() }.onChange(of: bypass) { clear() }
    }
    private func clear() { result = nil; error = nil }
    private func test() {
        clear()
        do {
            if !source.isEmpty && !RuleCondition.validBundleID(source) { throw RuleError.invalid("Use a source bundle identifier, or leave it empty for Unknown.") }
            let link = try IncomingLink(raw, sourceApplication: source.isEmpty ? nil : source)
            result = try routing.configuration().evaluate(link, available: Set(Destination.applications(for: link.url).map(\.bundleID)), forceChooser: bypass)
        } catch { self.error = error.localizedDescription }
    }
}
