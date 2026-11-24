import AppKit
import SwiftUI
import CloakToolsCore

@MainActor final class WorkspaceDefaultHandlers: DefaultHandlerSystem {
    static func application(at url: URL) -> HandlerApplication? {
        let resolved = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolved.path), let bundle = Bundle(url: resolved), let id = bundle.bundleIdentifier else { return nil }
        return .init(bundleID: id, name: (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? resolved.deletingPathExtension().lastPathComponent, url: resolved)
    }
    func current(for scheme: LinkScheme) -> HandlerApplication? {
        NSWorkspace.shared.urlForApplication(toOpen: scheme.probeURL).flatMap(Self.application)
    }
    func available(for scheme: LinkScheme) -> [HandlerApplication] {
        NSWorkspace.shared.urlsForApplications(toOpen: scheme.probeURL).compactMap(Self.application).sorted {
            $0.name == $1.name ? $0.url.path < $1.url.path : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    func set(_ application: HandlerApplication, for scheme: LinkScheme) async throws {
        guard let verified = Self.application(at: application.url), verified.isSameApplication(as: application) else { throw DefaultHandlerError.unavailable }
        try await NSWorkspace.shared.setDefaultApplication(at: verified.url, toOpenURLsWithScheme: scheme.rawValue)
    }
}

@MainActor @Observable final class DefaultHandlerSettings {
    let coordinator: DefaultHandlerCoordinator
    var current: [LinkScheme: HandlerApplication] = [:]
    var busy = false
    let isPreview: Bool
    init() {
        let own = WorkspaceDefaultHandlers.application(at: Bundle.main.bundleURL)!
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--preview-default-handlers") {
            coordinator = DefaultHandlerPreview.coordinator(own: own)
            isPreview = true; refresh(); return
        }
        #endif
        coordinator = .init(ownApplication: own, system: WorkspaceDefaultHandlers(), store: HandlerHistoryStore.standard)
        isPreview = false
        refresh()
    }
    func refresh() {
        current = Dictionary(uniqueKeysWithValues: [LinkRole.web, .email].flatMap { coordinator.observations(for: $0) }
            .compactMap { observation in observation.application.map { (observation.scheme, $0) } })
    }
    func ownedCount(_ role: LinkRole) -> Int { LinkScheme.schemes(for: role).filter { coordinator.isOwned(current[$0]) }.count }
    func summary(_ role: LinkRole) -> String {
        let schemes = LinkScheme.schemes(for: role)
        if role == .email { return current[.mailto]?.name ?? "No available app" }
        if let https = current[.https], let http = current[.http], https.isSameApplication(as: http) { return https.name }
        return schemes.map { "\($0.title): \(current[$0]?.name ?? "No available app")" }.joined(separator: " · ")
    }
}

private struct DefaultReviewRequest: Identifiable {
    let id = UUID()
    let role: LinkRole
    let kind: DefaultChangeKind
}

struct DefaultHandlerSection: View {
    @Bindable var settings: DefaultHandlerSettings
    var onRefresh: () -> Void = {}
    @State private var review: DefaultReviewRequest?
    var body: some View {
        Section {
            if settings.isPreview { Label("Preview only · system defaults are unchanged", systemImage: "testtube.2").font(.caption).foregroundStyle(.orange) }
            roleRow(.web)
            roleRow(.email)
            Button("Refresh Status", systemImage: "arrow.clockwise") { settings.refresh(); onRefresh() }.disabled(settings.busy)
        } header: { Text("Default link apps") } footer: {
            Text("Set up web and email links separately. Changes start only after your review; macOS may ask for confirmation.")
        }
        .sheet(item: $review) { DefaultHandlerReview(settings: settings, role: $0.role, kind: $0.kind) }
        .onAppear(perform: settings.refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in settings.refresh() }
    }
    private func roleRow(_ role: LinkRole) -> some View {
        HStack(spacing: 10) {
            Image(systemName: role == .web ? "globe" : "envelope").font(.title3).foregroundStyle(.blue).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(role == .web ? "Web links" : "Email links").fontWeight(.medium)
                Text(settings.summary(role)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if role == .web && settings.ownedCount(role) == 1 { Text("Partially using CloakTools").font(.caption).foregroundStyle(.orange) }
            }
            Spacer(minLength: 8)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions(role) }
                VStack(alignment: .trailing, spacing: 8) { actions(role) }
            }.fixedSize()
        }.padding(.vertical, 4).disabled(settings.busy)
    }
    @ViewBuilder private func actions(_ role: LinkRole) -> some View {
        if settings.ownedCount(role) < LinkScheme.schemes(for: role).count {
            Button("Set Up…") { review = .init(role: role, kind: .useCloakTools) }
                .accessibilityLabel(role == .web ? "Set up web link defaults" : "Set up email link default")
        }
        if settings.ownedCount(role) > 0 {
            Button("Restore…") { review = .init(role: role, kind: .restore) }
                .accessibilityLabel(role == .web ? "Restore web link defaults" : "Restore email link default")
        }
    }
}

struct DefaultHandlerReview: View {
    @Bindable var settings: DefaultHandlerSettings
    let role: LinkRole
    let kind: DefaultChangeKind
    @Environment(\.dismiss) private var dismiss
    @State private var observations: [HandlerObservation] = []
    @State private var history: [HandlerRestorePoint] = []
    @State private var alternatives: [LinkScheme: [HandlerApplication]] = [:]
    @State private var selected: [LinkScheme: URL] = [:]
    @State private var plan: DefaultChangePlan?
    @State private var result: DefaultChangeResult?
    @State private var error: String?
    @State private var applying = false
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DialogHeading(title: heading, subtitle: subtitle, symbol: role == .web ? "globe" : "envelope")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let result {
                        Label(result.message, systemImage: result.complete ? "checkmark.circle" : "exclamationmark.triangle")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(result.observations, id: \.scheme) { observation in
                                HStack {
                                    Text(observation.scheme.title).fontWeight(.medium)
                                    Spacer()
                                    Text(observation.application?.name ?? "No available app").foregroundStyle(.secondary)
                                }.accessibilityElement(children: .combine)
                            }
                        }.frame(maxWidth: .infinity).modifier(DialogCard())
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(observations, id: \.scheme) { observation in
                                if observation.scheme != observations.first?.scheme { Divider() }
                                schemeRow(observation)
                            }
                        }.modifier(DialogCard())
                        Text(kind == .useCloakTools
                             ? "CloakTools will receive these links and use your chooser or rules. Previous apps are saved locally so you can restore them later."
                             : "Only link types still using this copy of CloakTools can change. Apps chosen outside CloakTools are kept.")
                            .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if role == .email { Text("Email links prepare a draft. Your mail app chooses the From account; no mail is sent.").font(.caption).foregroundStyle(.secondary) }
                        if kind == .useCloakTools {
                            Text(role == .web ? "Email links stay as they are." : "Web links stay as they are.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }.scrollBounceBehavior(.basedOnSize).disabled(applying)
            OperationFeedback(activity: applying ? "Waiting for macOS…" : nil, error: error)
            DialogFooter {
                if result == nil {
                    Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction).modifier(DialogActionStyle())
                }
            } actions: {
                if let result, !result.complete {
                    Button("Review Again", action: load).modifier(DialogActionStyle())
                }
                if result == nil {
                    Button(kind == .useCloakTools ? "Use CloakTools" : "Restore Apps", action: apply)
                        .keyboardShortcut(.defaultAction).disabled(plan == nil || plan?.steps.isEmpty == true)
                        .modifier(DialogActionStyle(prominent: true))
                } else {
                    DialogDoneButton { dismiss() }
                }
            }.disabled(applying)
        }.padding(20).frame(width: 460, height: result == nil ? (role == .web ? 380 : 330) : (role == .web ? 300 : 280))
            .interactiveDismissDisabled(applying).onAppear(perform: load)
            .onChange(of: selected) { updatePlan() }
            .onExitCommand { if !applying { dismiss() } }
    }
    private var heading: String {
        if let result { return result.complete ? "Defaults updated" : "Review current apps" }
        return kind == .useCloakTools ? (role == .web ? "Set up web links" : "Set up email links") : (role == .web ? "Restore web apps" : "Restore email app")
    }
    private var subtitle: String {
        if settings.isPreview { return "Preview only. System defaults are unchanged." }
        if result != nil { return "Checked against your Mac’s current defaults." }
        return kind == .useCloakTools ? "Review where these links will open." : "Choose the apps to return to."
    }
    @ViewBuilder private func schemeRow(_ observation: HandlerObservation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(observation.scheme.title).fontWeight(.medium)
                Spacer()
                Text(observation.application?.name ?? "No available app").foregroundStyle(.secondary).lineLimit(2)
            }.accessibilityElement(children: .combine)
            if kind == .useCloakTools {
                if settings.coordinator.isOwned(observation.application) {
                    Label("Already using CloakTools", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Change to CloakTools", systemImage: "arrow.turn.down.right").font(.callout)
                    if observation.application == nil || observation.application?.bundleID == settings.coordinator.ownApplication.bundleID {
                        Text("No previous app can be saved for this link type. You can choose an available app when restoring.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else if settings.coordinator.isOwned(observation.application) {
                Picker("Restore to", selection: Binding(get: { selected[observation.scheme] }, set: { selected[observation.scheme] = $0 })) {
                    Text("Choose an app").tag(nil as URL?)
                    ForEach(alternatives[observation.scheme] ?? []) { app in
                        Text(app.name).tag(Optional(app.url)).help(app.url.path)
                    }
                }.accessibilityLabel("Restore \(observation.scheme.title) to")
                if let previous = history.first(where: { $0.scheme == observation.scheme })?.previous {
                    let available = settings.coordinator.previousAvailable(for: observation.scheme, points: history) != nil
                    Text(available ? "Previous app: \(previous.name)" : "\(previous.name) is unavailable. Choose another app.").font(.caption).foregroundStyle(.secondary)
                } else { Text("No previous app was saved. Choose an available app.").font(.caption).foregroundStyle(.secondary) }
            } else {
                Text("Kept as it is — this link type is no longer using CloakTools.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func load() {
        error = nil; result = nil; plan = nil
        settings.refresh(); observations = settings.coordinator.observations(for: role)
        do {
            history = try settings.coordinator.history(); alternatives = [:]; selected = [:]
            for scheme in LinkScheme.schemes(for: role) {
                alternatives[scheme] = settings.coordinator.alternatives(for: scheme)
                selected[scheme] = settings.coordinator.previousAvailable(for: scheme, points: history)?.url
            }
            updatePlan()
        } catch { self.error = "Recovery information could not be read. No defaults changed. \(error.localizedDescription)" }
    }
    private func updatePlan() {
        guard !applying, result == nil else { return }
        do {
            let apps = Dictionary(uniqueKeysWithValues: selected.compactMap { scheme, url in
                alternatives[scheme]?.first(where: { $0.url == url }).map { (scheme, $0) }
            })
            let proposed = try settings.coordinator.prepare(role: role, kind: kind, restoring: apps)
            // Changing a picker must not silently replace the review's original system snapshot.
            guard proposed.observations == observations else { throw DefaultHandlerError.staleReview }
            plan = proposed; error = nil
        } catch {
            plan = nil
            if kind == .restore && observations.contains(where: { settings.coordinator.isOwned($0.application) && selected[$0.scheme] == nil }) { self.error = nil }
            else { self.error = error.localizedDescription }
        }
    }
    private func apply() {
        guard let plan, !applying else { return }
        applying = true; settings.busy = true; error = nil
        Task { @MainActor in
            defer { applying = false; settings.busy = false; settings.refresh() }
            do { result = try await settings.coordinator.execute(plan) }
            catch {
                result = .init(observations: settings.coordinator.observations(for: role), complete: false, message: error.localizedDescription)
            }
        }
    }
}
