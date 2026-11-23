import SwiftUI
import AppKit
import CloakToolsCore

struct Destination: Identifiable, Equatable {
    let url: URL
    let name: String
    let bundleID: String
    var id: URL { url }
    var reference: DestinationReference { .init(bundleID: bundleID, name: name) }
    static func ordered(_ apps: [Destination], preferences: DestinationPreferences) -> [Destination] {
        preferences.ordered(apps.map(\.reference)).compactMap { reference in apps.first { $0.bundleID == reference.bundleID } }
    }
    @MainActor static func applications(for url: URL) -> [Destination] {
        let candidates = NSWorkspace.shared.urlsForApplications(toOpen: url).compactMap { app -> Destination? in
            guard FileManager.default.fileExists(atPath: app.path), let bundle = Bundle(url: app), let id = bundle.bundleIdentifier,
                  IncomingLink.permitsDestination(bundleID: id, appURL: app, ownURL: Bundle.main.bundleURL) else { return nil }
            return Destination(url: app, name: (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? app.deletingPathExtension().lastPathComponent, bundleID: id)
        }
        return Dictionary(grouping: candidates, by: \.bundleID).values.compactMap { copies in
            guard let first = copies.first else { return nil }
            let preferred = NSWorkspace.shared.urlForApplication(withBundleIdentifier: first.bundleID)
            return copies.first(where: { $0.url == preferred }) ?? copies.sorted { $0.url.path < $1.url.path }.first
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    @MainActor static func applications(for role: LinkRole) -> [Destination] {
        let urls = role == .web ? ["https://example.com", "http://example.com"] : ["mailto:hello@example.com"]
        var apps: [String: Destination] = [:]
        for raw in urls { for app in applications(for: URL(string: raw)!) { apps[app.bundleID] = app } }
        return apps.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

@MainActor @Observable
final class LinkRouter: NSObject, NSWindowDelegate {
    var link: IncomingLink?
    var destinations: [Destination] = []
    var selected: URL?
    var error: String?
    var opening = false
    var explanation: String?
    var lastRoute: String?
    private var automaticRule: RoutingRule?
    private var automaticFallback = false
    private var destinationPreferences = DestinationPreferences()
    private struct Request {
        let link: IncomingLink
        let configuration: RoutingConfiguration?
        let forceChooser: Bool
    }
    private var queue: [Request] = []
    private var guardState = LoopGuard()
    private var window: NSWindow?
    func receive(_ raw: String, forceChooser: Bool = false, sourceApplication: String? = nil) {
        do {
            let incoming = try IncomingLink(raw, sourceApplication: sourceApplication)
            guard queue.count < 20 else { return }
            let request = Request(link: incoming, configuration: try? AppModel.shared.routing.configuration(), forceChooser: forceChooser)
            if link != nil { queue.append(request) } else { begin(request) }
        } catch { AppModel.shared.showError(error) }
    }
    private func begin(_ request: Request) {
        destinationPreferences = request.configuration?.destinations[request.link.role] ?? .init()
        link = request.link; refresh(); error = nil; explanation = nil; automaticRule = nil; automaticFallback = false
        // Recheck when draining queued links: a preceding dispatch may now be a loop.
        if !guardState.permits(request.link) {
            error = "An application returned this link to CloakTools. Automatic reopening was stopped. Choose another app."
        } else if request.forceChooser {
            explanation = "Choose an app for this link. Rules and fallback are bypassed for this one opening."
        } else if let configuration = request.configuration {
            let decision = configuration.evaluate(request.link, available: Set(destinations.map(\.bundleID)))
            explanation = decision.reason
            if let id = decision.destinationBundleID, let destination = destinations.first(where: { $0.bundleID == id }) {
                selected = destination.url; automaticRule = decision.rule; automaticFallback = decision.fallback != nil; openOnce(); return
            }
        } else { error = "Routing settings could not be read. Choose an app, then review Open With settings." }
        showWindow()
    }
    private func showWindow() {
        guard let incoming = link, window == nil else { return }
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 448, height: 430), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        panel.title = incoming.role == .web ? "Open Web Link" : "Open Email Link"
        panel.contentViewController = NSHostingController(rootView: LinkChooser(router: self))
        panel.titleVisibility = .hidden; panel.titlebarAppearsTransparent = true
        panel.contentMinSize = NSSize(width: 420, height: 430); panel.setContentSize(NSSize(width: 448, height: 480)); panel.isReleasedWhenClosed = false
        panel.delegate = self; panel.center(); window = panel
        panel.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    func refresh() {
        guard let link else { return }
        destinations = Destination.ordered(Destination.applications(for: link.url), preferences: destinationPreferences)
        if !destinations.contains(where: { $0.url == selected }) { selected = destinations.first?.url }
    }
    func openOnce() {
        guard !opening, let link, let destination = destinations.first(where: { $0.url == selected }) else { return }
        guard Destination.applications(for: link.url).contains(destination), FileManager.default.fileExists(atPath: destination.url.path),
              Bundle(url: destination.url)?.bundleIdentifier == destination.bundleID,
              IncomingLink.permitsDestination(bundleID: Bundle(url: destination.url)?.bundleIdentifier, appURL: destination.url, ownURL: Bundle.main.bundleURL) else {
            error = "This app is no longer available. Choose another destination."; automaticRule = nil; automaticFallback = false; refresh(); showWindow(); return
        }
        opening = true; error = nil; guardState.recordDispatch(link)
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([link.url], withApplicationAt: destination.url, configuration: configuration) { [weak self] _, failure in
            Task { @MainActor in
                guard let self else { return }
                self.opening = false
                if let failure { self.error = "Couldn’t open \(destination.name): \(failure.localizedDescription)"; self.automaticRule = nil; self.automaticFallback = false; self.refresh(); self.showWindow() }
                else {
                    self.lastRoute = self.automaticRule.map { "“\($0.name)” → \(destination.name)" } ?? "\(self.automaticFallback ? "Fallback" : "Open Once") → \(destination.name)"
                    self.finish()
                }
            }
        }
    }
    func copyLink() -> Bool {
        guard let link else { return false }
        let item = NSPasteboardItem()
        guard item.setString(link.original, forType: .string) else { error = "macOS could not prepare the link for copying."; return false }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { error = "macOS could not write to the clipboard. Try copying again."; return false }
        return true
    }
    func finish() {
        guard !opening else { return }
        window?.delegate = nil; window?.close(); window = nil; link = nil; error = nil; selected = nil; explanation = nil; automaticRule = nil; automaticFallback = false
        if !queue.isEmpty { let next = queue.removeFirst(); begin(next) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if opening { return false }; finish(); return false }
}

struct LinkChooser: View {
    @Bindable var router: LinkRouter
    @State private var copied = false
    @State private var editingRule: RoutingRule?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let link = router.link {
                DialogHeading(title: link.role == .web ? "Open link" : "Open email",
                              subtitle: "Choose where it goes.",
                              symbol: link.role == .web ? "arrow.up.forward.app" : "envelope")
                VStack(alignment: .leading, spacing: 6) {
                    Text(link.original).font(.callout).lineLimit(2).truncationMode(.middle)
                        .textSelection(.enabled).help(link.original)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Original link").accessibilityValue(link.original)
                    Text("From \(link.sourceApplication ?? "Unknown source")").font(.caption).foregroundStyle(.secondary)
                }.modifier(DialogCard())
                if let explanation = router.explanation {
                    Text(explanation).font(.caption).foregroundStyle(.secondary).lineLimit(3).help(explanation)
                }
                if router.destinations.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No compatible apps", systemImage: "app.dashed").fontWeight(.medium)
                        Text("Install a \(link.role == .web ? "browser" : "mail app"), then refresh.").foregroundStyle(.secondary)
                        Button("Refresh", action: router.refresh)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                } else {
                    List(router.destinations, selection: $router.selected) { destination in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: destination.url.path)).resizable().frame(width: 28, height: 28).accessibilityHidden(true)
                            Text(destination.name).fontWeight(.medium)
                            Spacer()
                            if router.selected == destination.url { Image(systemName: "checkmark").fontWeight(.semibold).accessibilityHidden(true) }
                        }.padding(.vertical, 3).tag(destination.url)
                            .help(destination.url.path)
                            .listRowSeparator(.hidden)
                    }.listStyle(.plain).scrollContentBackground(.hidden)
                        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
                        .clipShape(.rect(cornerRadius: 12))
                        .accessibilityLabel("Destination applications")
                }
                if link.role == .email {
                    Text("Prepares a draft. Your mail app chooses the From account.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Create Rule…", systemImage: "arrow.triangle.branch") {
                        if let destination = router.destinations.first(where: { $0.url == router.selected }) {
                            editingRule = AppModel.shared.routing.draft(for: link, destination: destination)
                        }
                    }.buttonStyle(.borderless).disabled(router.selected == nil || router.opening)
                    Spacer()
                }
            }
            if let error = router.error {
                ScrollView { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.callout) }.frame(maxHeight: 60)
            }
            DialogFooter {
                Button("Cancel", role: .cancel, action: router.finish).keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
            } actions: {
                Button(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "link") { copied = router.copyLink() }
                    .keyboardShortcut("c", modifiers: [.command, .shift]).modifier(DialogActionStyle())
                Button(router.opening ? "Opening…" : "Open Once", action: router.openOnce)
                    .keyboardShortcut(.defaultAction).disabled(router.selected == nil).modifier(DialogActionStyle(prominent: true))
            }
        }.padding(20).frame(minWidth: 420, minHeight: 380)
            .onChange(of: router.link?.id) { copied = false }
            .sheet(item: $editingRule) { RuleEditor(draft: $0, routing: AppModel.shared.routing) }
            .transaction { if reduceMotion { $0.animation = nil } }
    }
}
