import AppKit
import SwiftUI
import CloakToolsCore

private struct DestinationEditorRequest: Identifiable {
    let role: LinkRole
    var id: String { role.rawValue }
}

struct DestinationSettingsSection: View {
    @Bindable var routing: RoutingSettings
    @State private var editing: DestinationEditorRequest?
    @State private var available: [LinkRole: Set<String>] = [:]
    var body: some View {
        Section {
            if let error = routing.destinationError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            ForEach(LinkRole.allCases, id: \.self) { role in
                HStack(spacing: 10) {
                    Image(systemName: role == .web ? "safari" : "envelope.open").font(.title3).foregroundStyle(.blue).frame(width: 26).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(role == .web ? "Web destinations" : "Email destinations").fontWeight(.medium)
                        Text(summary(role)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if let fallback = routing.destinations[role].fallback, available[role]?.contains(fallback.bundleID) == false {
                            Label("Fallback unavailable · chooser will open", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 8)
                    Button("Manage…") { editing = .init(role: role) }
                        .accessibilityLabel(role == .web ? "Manage web destinations" : "Manage email destinations")
                        .disabled(routing.destinationError != nil)
                }.padding(.vertical, 4)
            }
        } header: { Text("Destinations & fallback") } footer: {
            Text("Rules take priority. Pin apps to put them first in the chooser; choose what happens when no rule matches.")
        }
        .sheet(item: $editing) { DestinationEditor(role: $0.role, routing: routing) }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }
    private func summary(_ role: LinkRole) -> String {
        let preferences = routing.destinations[role]
        let fallback = preferences.fallback.map { "Fallback: \($0.name)" } ?? "Fallback: Show chooser"
        return preferences.pinned.isEmpty ? fallback : "\(fallback) · \(preferences.pinned.count) pinned"
    }
    private func refresh() {
        available = Dictionary(uniqueKeysWithValues: LinkRole.allCases.map { ($0, Set(Destination.applications(for: $0).map(\.bundleID))) })
    }
}

struct DestinationEditor: View {
    let role: LinkRole
    let routing: RoutingSettings
    @Environment(\.dismiss) private var dismiss
    @State private var observed: DestinationPreferences?
    @State private var draft = DestinationPreferences()
    @State private var apps: [Destination] = []
    @State private var supported: [String: String] = [:]
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: role == .web ? "Web destinations" : "Email destinations",
                          subtitle: "Your apps, in the order you prefer.", symbol: role == .web ? "safari" : "envelope.open")
            VStack(alignment: .leading, spacing: 8) {
                Picker("When no rule matches", selection: fallbackSelection) {
                    Text("Show chooser").tag("")
                    Divider()
                    ForEach(apps) { Text($0.name).tag($0.bundleID) }
                    if let fallback = draft.fallback, !apps.contains(where: { $0.bundleID == fallback.bundleID }) {
                        Text("\(fallback.name) (unavailable)").tag(fallback.bundleID)
                    }
                }
                if let fallback = draft.fallback {
                    Label(apps.contains(where: { $0.bundleID == fallback.bundleID })
                          ? "Unmatched links open in \(fallback.name)."
                          : "\(fallback.name) is unavailable. Links will show the chooser.",
                          systemImage: apps.contains(where: { $0.bundleID == fallback.bundleID }) ? "arrow.up.forward.app" : "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else { Text("Choose an app each time a link has no matching rule.").font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).modifier(DialogCard())
            HStack {
                Text("Apps in chooser order").font(.callout).fontWeight(.medium)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: refreshApps).buttonStyle(.borderless)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(rows) { reference in
                        destinationRow(reference)
                        if reference.id != rows.last?.id { Divider().padding(.leading, 42) }
                    }
                    if rows.isEmpty {
                        ContentUnavailableView("No compatible apps", systemImage: "app.dashed", description: Text("Install a compatible app, then refresh."))
                    }
                }.frame(maxWidth: .infinity).padding(10)
            }.scrollBounceBehavior(.basedOnSize)
                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.08)))
            Text("Pins change order only. Other compatible apps stay available. These choices do not change your Mac’s defaults.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            DialogFooter {
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
            } actions: {
                Button("Save Changes", action: save).keyboardShortcut(.defaultAction)
                    .disabled(observed == nil || draft == observed).modifier(DialogActionStyle(prominent: true))
            }
        }.padding(20).frame(width: 480, height: 480).onAppear(perform: load)
    }
    private var fallbackSelection: Binding<String> {
        .init(get: { draft.fallback?.bundleID ?? "" }, set: { id in
            guard id != (draft.fallback?.bundleID ?? "") else { return }
            draft.fallback = apps.first { $0.bundleID == id }?.reference
        })
    }
    private var rows: [DestinationReference] {
        draft.pinned.map { pin in apps.first { $0.bundleID == pin.bundleID }?.reference ?? pin }
            + apps.filter { app in !draft.pinned.contains { $0.bundleID == app.bundleID } }.map(\.reference)
    }
    private func destinationRow(_ reference: DestinationReference) -> some View {
        let app = apps.first { $0.bundleID == reference.bundleID }
        let index = draft.pinned.firstIndex { $0.bundleID == reference.bundleID }
        return HStack(spacing: 10) {
            Group {
                if let app { Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable() }
                else { Image(systemName: "app.dashed").resizable().padding(3).foregroundStyle(.secondary) }
            }.frame(width: 30, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(reference.name).font(.callout).fontWeight(.medium).lineLimit(1)
                Text(app == nil ? "Unavailable · kept until unpinned" : (supported[reference.bundleID] ?? "Available"))
                    .font(.caption).foregroundStyle(app == nil ? .orange : .secondary).lineLimit(2)
            }.accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            if let index {
                Menu {
                    Button("Move Up") { draft.pinned.swapAt(index, index - 1) }.disabled(index == 0)
                    Button("Move Down") { draft.pinned.swapAt(index, index + 1) }.disabled(index == draft.pinned.count - 1)
                    Divider()
                    Button("Unpin") { draft.pinned.remove(at: index) }
                } label: { Label("Pinned", systemImage: "pin.fill").font(.caption) }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Pinned app actions for \(reference.name)")
            } else {
                Button { draft.pinned.append(reference) } label: { Image(systemName: "pin") }
                    .buttonStyle(.borderless).help("Pin \(reference.name)").accessibilityLabel("Pin \(reference.name)")
                    .disabled(draft.pinned.count >= 32)
            }
        }.padding(.vertical, 9).padding(.horizontal, 4)
    }
    private func load() {
        do { let current = try routing.destinationSnapshot()[role]; observed = current; draft = current; error = nil }
        catch { self.error = error.localizedDescription }
        refreshApps()
    }
    private func refreshApps() {
        apps = Destination.applications(for: role)
        let schemes = LinkScheme.schemes(for: role)
        let compatibility = schemes.map { ($0, Set(Destination.applications(for: $0.probeURL).map(\.bundleID))) }
        supported = Dictionary(uniqueKeysWithValues: apps.map { app in
            (app.bundleID, compatibility.filter { $0.1.contains(app.bundleID) }.map { $0.0.title }.joined(separator: " · "))
        })
    }
    private func save() {
        guard let observed else { return }
        refreshApps()
        do {
            if let fallback = draft.fallback, fallback != observed.fallback, !apps.contains(where: { $0.bundleID == fallback.bundleID }) {
                throw RuleError.invalid("The selected fallback app is no longer available. Choose another app or Show chooser.")
            }
            try routing.saveDestinations(draft, for: role, replacing: observed); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
